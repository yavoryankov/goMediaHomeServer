#!/usr/bin/env python3
"""Local v2 bridge: download permitted media and upload it to goMediaHomeServer."""

import cgi
import json
import os
import shutil
import site
import subprocess
import sys
import tempfile
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, quote, urlparse
from urllib.request import Request, urlopen

HOST = "127.0.0.1"
PORT = 7071
DEFAULT_API = os.environ.get("GOMEDIA_SERVER_API", "http://YOUR-IMAC-IP:8095/api/v1")
RECORDINGS = {}


def emit(handler, kind, message, **extra):
    payload = {"type": kind, "message": message, **extra}
    handler.wfile.write((json.dumps(payload, ensure_ascii=False) + "\n").encode())
    handler.wfile.flush()


def cookie_file(cookies, directory):
    if not cookies:
        return None
    path = Path(directory) / "cookies.txt"
    with path.open("w", encoding="utf-8") as output:
        output.write("# Netscape HTTP Cookie File\n")
        for cookie in cookies:
            domain = str(cookie.get("domain", ""))
            output.write("\t".join([
                domain,
                "TRUE" if domain.startswith(".") else "FALSE",
                str(cookie.get("path", "/")),
                "TRUE" if cookie.get("secure") else "FALSE",
                str(int(cookie.get("expirationDate", 0) or 0)),
                str(cookie.get("name", "")),
                str(cookie.get("value", "")),
            ]) + "\n")
    return path


def multipart_upload(api, destination, file_path):
    parsed = urlparse(api)
    if parsed.scheme not in {"http", "https"} or not parsed.netloc:
        raise ValueError(f"Invalid media server API URL: {api!r}. Use http://HOST:8095/api/v1")
    if "YOUR-IMAC-IP" in parsed.netloc or "YOUR-" in parsed.netloc:
        raise ValueError("The media server API address is still a placeholder. Set it in the extension settings.")
    boundary = "----goMediaHomeServerBoundary"
    name = file_path.name
    data = file_path.read_bytes()
    body = (
        f"--{boundary}\r\nContent-Disposition: form-data; name=\"path\"\r\n\r\n{destination}\r\n"
        f"--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"{name}\"\r\n"
        f"Content-Type: application/octet-stream\r\n\r\n"
    ).encode() + data + f"\r\n--{boundary}--\r\n".encode()
    request = Request(api.rstrip("/") + "/upload", data=body, method="POST")
    request.add_header("Content-Type", f"multipart/form-data; boundary={boundary}")
    try:
        response_context = urlopen(request, timeout=120)
    except OSError as error:
        raise RuntimeError(f"Cannot reach media server at {api}: {error}") from error
    with response_context as response:
        if response.status < 200 or response.status >= 300:
            raise RuntimeError(f"Media server upload failed with HTTP {response.status}")
        return json.loads(response.read().decode())


def configured_api(value):
    api = str(value or DEFAULT_API).strip()
    return api


def downloader_command(path=None):
    """Use yt-dlp through the active Python runtime on macOS, Windows, and Linux."""
    try:
        import yt_dlp  # noqa: F401
        command = [sys.executable, "-m", "yt_dlp"]
        deno = shutil.which("deno", path=path)
        if deno:
            command += ["--js-runtimes", f"deno:{deno}"]
        return command
    except ImportError:
        executable = shutil.which("yt-dlp")
        if executable:
            return [executable]
        raise RuntimeError(
            "yt-dlp is not installed. Run the platform setup command from README.md "
            "and restart the bridge."
        )


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def end_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        super().end_headers()

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_GET(self):
        if urlparse(self.path).path == "/health":
            self.send_json(200, {"status": "ok", "service": "gomediahome-bridge"})
            return
        if urlparse(self.path).path == "/api/folders":
            self.proxy_folders()
            return
        self.send_json(404, {"error": "Not found"})

    def proxy_folders(self):
        query = parse_qs(urlparse(self.path).query)
        api = configured_api(query.get("api", [DEFAULT_API])[0])
        path = query.get("path", [""])[0]
        parsed = urlparse(api)
        if parsed.scheme not in {"http", "https"} or not parsed.netloc:
            self.send_json(400, {"error": f"Invalid media server API URL: {api}"})
            return
        target = api.rstrip("/") + "/folders?path=" + quote(path, safe="")
        try:
            with urlopen(target, timeout=20) as response:
                body = response.read()
                self.send_response(response.status)
                self.send_header("Content-Type", "application/json; charset=utf-8")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
        except Exception as error:
            self.send_json(502, {"error": f"Cannot read folders from media server: {error}"})

    def do_POST(self):
        path = urlparse(self.path).path
        if path == "/api/recordings/start":
            self.start_recording()
            return
        if path == "/api/recordings/chunk":
            self.record_chunk()
            return
        if path == "/api/recordings/finish":
            self.finish_recording()
            return
        if path == "/api/recordings/cancel":
            self.cancel_recording()
            return
        if path not in {"/tools/youtube/download", "/tools/vimeo/download"}:
            self.send_error(404)
            return
        response_started = False
        try:
            length = int(self.headers.get("Content-Length", "0"))
            request = json.loads(self.rfile.read(length))
            urls = [line.strip() for line in str(request.get("urls", "")).splitlines() if line.strip()]
            if not urls:
                raise ValueError("No video URL was provided.")
            api = configured_api(request.get("media_server_api"))
            destination = str(request.get("destination_path") or "").strip().strip("/")
            if not destination:
                raise ValueError("A destination folder is required.")
            process_env = os.environ.copy()
            user_bin = Path(site.getuserbase()) / "bin"
            process_env["PATH"] = os.pathsep.join([str(user_bin), process_env.get("PATH", "")])
            downloader = downloader_command(process_env["PATH"])

            self.send_response(200)
            self.send_header("Content-Type", "application/x-ndjson; charset=utf-8")
            self.send_header("Cache-Control", "no-cache")
            self.end_headers()
            response_started = True
            with tempfile.TemporaryDirectory(prefix="gomedia-download-") as temp:
                temp_dir = Path(temp)
                cookies = cookie_file(request.get("cookies") or [], temp_dir)
                template = str(temp_dir / "%(title).120s [%(id)s].%(ext)s")
                command = downloader + ["--no-playlist", "--newline", "--no-colors", "--windows-filenames", "-o", template]
                if cookies:
                    command += ["--cookies", str(cookies)]
                fmt = str(request.get("format") or "video")
                if fmt == "audio":
                    command += ["-x", "--audio-format", "mp3", "--audio-quality", "0"]
                elif fmt == "subtitles":
                    command += ["--skip-download", "--write-subs", "--write-auto-subs", "--sub-langs", "all", "--sub-format", "srt/vtt/best", "--convert-subs", "srt"]
                else:
                    command += ["-f", "bv*[height<=1080][ext=mp4]+ba[ext=m4a]/b[height<=1080][ext=mp4]/b[height<=1080]", "--merge-output-format", "mp4"]
                command += urls
                emit(self, "stage", "Downloading media…")
                try:
                    import certifi
                    process_env.setdefault("SSL_CERT_FILE", certifi.where())
                    process_env.setdefault("REQUESTS_CA_BUNDLE", certifi.where())
                except ImportError:
                    pass
                process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, env=process_env)
                recent_output = []
                for line in process.stdout or []:
                    line = line.strip()
                    if line:
                        recent_output.append(line[-500:])
                        recent_output = recent_output[-8:]
                        emit(self, "stage", line[-500:])
                if process.wait() != 0:
                    details = " | ".join(recent_output)
                    raise RuntimeError(f"The downloader failed: {details or 'yt-dlp returned a non-zero exit code.'}")
                files = [path for path in temp_dir.iterdir() if path.is_file() and path.name != "cookies.txt"]
                if not files:
                    raise RuntimeError("The download completed but no output file was found.")
                for file_path in files:
                    emit(self, "stage", f"Uploading {file_path.name} to {destination}…")
                    result = multipart_upload(api, destination, file_path)
                    emit(self, "done", f"Uploaded: {result.get('path', file_path.name)}", path=result.get("path", ""))
        except Exception as error:
            try:
                if response_started:
                    emit(self, "error", str(error))
                else:
                    self.send_json(500, {"message": str(error)})
            except (BrokenPipeError, ConnectionResetError):
                pass

    def send_json(self, status, payload):
        body = json.dumps(payload, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def start_recording(self):
        length = int(self.headers.get("Content-Length", "0"))
        request = json.loads(self.rfile.read(length) or b"{}")
        session_id = uuid.uuid4().hex
        temp_dir = Path(tempfile.mkdtemp(prefix="gomedia-recording-"))
        filename = Path(str(request.get("filename") or "capture")).name
        if not filename.lower().endswith(".webm"):
            filename += ".webm"
        output = temp_dir / filename
        RECORDINGS[session_id] = {
            "directory": str(request.get("directory") or "Recordings").strip("/"),
            "api": configured_api(request.get("media_server_api")),
            "output": output,
            "temp_dir": temp_dir,
        }
        self.send_json(201, {"session_id": session_id, "path": RECORDINGS[session_id]["directory"] + "/" + filename})

    def record_chunk(self):
        session_id = parse_qs(urlparse(self.path).query).get("session_id", [""])[0]
        session = RECORDINGS.get(session_id)
        if not session:
            self.send_json(404, {"error": "Recording session not found."})
            return
        length = int(self.headers.get("Content-Length", "0"))
        with session["output"].open("ab") as output:
            output.write(self.rfile.read(length))
        self.send_json(200, {"ok": True})

    def finish_recording(self):
        session_id = parse_qs(urlparse(self.path).query).get("session_id", [""])[0]
        session = RECORDINGS.pop(session_id, None)
        if not session:
            self.send_json(404, {"error": "Recording session not found."})
            return
        try:
            result = multipart_upload(session["api"], session["directory"], session["output"])
            self.send_json(200, {"ok": True, "path": result.get("path", "")})
        except Exception as error:
            self.send_json(500, {"message": str(error)})
        finally:
            shutil.rmtree(session["temp_dir"], ignore_errors=True)

    def cancel_recording(self):
        session_id = parse_qs(urlparse(self.path).query).get("session_id", [""])[0]
        session = RECORDINGS.pop(session_id, None)
        if session:
            shutil.rmtree(session["temp_dir"], ignore_errors=True)
        self.send_json(200, {"ok": True})


if __name__ == "__main__":
    print(f"goMediaHomeServer downloader bridge listening on http://{HOST}:{PORT}")
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
