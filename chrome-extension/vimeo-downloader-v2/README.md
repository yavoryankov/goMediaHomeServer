# goMediaHomeServer Media Downloader v2

This is a new, separate version of the Chrome extension. The original extension in `MediaPlatform` is not modified.

## What is new

- YouTube and Vimeo URL detection.
- Persistent extension settings page.
- Configurable goMediaHomeServer API URL.
- Configurable destination folder relative to the media library.
- Configurable local downloader service URL.
- The download request includes the configured media server destination.

## Install the extension

1. Open `chrome://extensions`.
2. Enable **Developer mode**.
3. Select **Load unpacked**.
4. Choose this directory.
5. Open the extension details and configure **Downloader settings**.

Recommended settings:

```text
Media server API URL:       http://YOUR-IMAC-IP:8095/api/v1
Destination folder:         Yavor/Courses/Arestovich
Local download bridge:      http://127.0.0.1:7071
Local recorder service:     http://127.0.0.1:7071
```

The destination is a relative path inside the configured media library. The v2 `bridge.py` downloads the media with `yt-dlp` and uploads the completed file through the media server `/api/v1/upload` endpoint. The recorder service remains a separate local service for Chrome tab capture.

The real LAN address must be entered in the extension settings. For a local bridge-only override, set `GOMEDIA_SERVER_API` before starting `bridge.py`; do not commit that local value.

## Run the local bridge

The bridge is written in portable Python and works on Apple Silicon Macs, Intel Macs, Windows, and Linux. It listens only on `127.0.0.1:7071`; the media server address is configured in the extension settings.

Install Python 3.10 or newer and Deno 2 or newer, then run the matching commands from this directory. Deno is used by yt-dlp to solve current YouTube JavaScript challenges.

### macOS and Linux

```bash
python3 -m pip install --user -r requirements.txt
python3 bridge.py
```

### Windows PowerShell

```powershell
py -3 -m pip install --user -r requirements.txt
py -3 bridge.py
```

If `py` is not available, use `python` instead. The bridge invokes `yt-dlp` through the active Python interpreter, so it does not depend on `/usr/local/bin`, Intel Homebrew, ARM Homebrew, or a Windows-specific executable path.

Install Deno from [deno.com](https://deno.com/) or with the package manager for your operating system. Make sure `deno --version` works in the same terminal before starting the bridge.

To verify the bridge before using the extension, open:

```text
http://127.0.0.1:7071/health
```

It should return a JSON response with `"status": "ok"`.

For audio downloads, `ffmpeg` must also be installed and available on `PATH` on the client computer. Video downloads use the formats supported by the installed `yt-dlp` version.

This version is intentionally isolated under the `goMediaHomeServer` project. It does not change the original `MediaPlatform` extension or server.
