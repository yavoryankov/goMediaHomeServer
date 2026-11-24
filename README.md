# goMediaHomeServer

Personal media server for a local LAN library. The project provides a Go backend, a web administration interface, and client folders for iOS and Android applications.

## Features

- Browse files and directories through the web admin interface.
- Upload files and create folders.
- Search by file name, path, and keywords.
- Manage keywords for files.
- Stream media files with HTTP Range support.
- Use the iOS API from devices on the local network.
- Store the media index and metadata in SQLite.

## Requirements

- Go 1.23 or newer.
- A local media directory.
- Network access between the client device and the server.

## Full server installation

1. Install Go 1.23 or newer.
2. Clone the repository and enter the project directory:

```sh
git clone <YOUR-GITHUB-REPOSITORY-URL> goMediaHomeServer
cd goMediaHomeServer
```

3. Create the configuration and choose a media directory:

```sh
cp config.example.json config.json
mkdir -p MediaHomeLibrary data
```

Edit `config.json` and set `media_root` to an absolute path for a production installation. Keep `config.json` private; only `config.example.json` belongs in Git.

4. Download dependencies, verify, and start the server:

```sh
go mod download
go test ./...
go run ./cmd/gomediahomeserver
```

Open `http://127.0.0.1:8095` locally. From another LAN device, use
`http://SERVER-LAN-IP:8095`.

For the iMac setup, copy `config.imac.example.json` to `config.json`, replace
`YOUR_USERNAME`, and use the absolute media and database paths for that Mac.

## Run locally

```sh
cp config.example.json config.json
go run ./cmd/gomediahomeserver
```

The default web interface and API are available at:

```text
http://127.0.0.1:8095
```

## Build ready-to-run server packages

The server can be packaged without requiring end users to install Go. From the
repository root, run:

```sh
VERSION=1.0.0 ./scripts/build-release.sh
```

This creates archives in `dist/` for macOS Intel and Apple Silicon, Linux
amd64 and arm64, and Windows amd64. Each archive contains the server binary,
`config.example.json`, the license, and deployment examples. Copy
`config.example.json` to `config.json`, set the media and database paths, then
run the included binary. The generated `dist/` directory is intentionally
ignored by Git; publish these archives as GitHub Release assets.

For an iMac LAN installation, copy `config.imac.example.json` to
`config.json`, replace `YOUR_USERNAME`, and start the server from the project directory.
Do not commit the machine-specific `config.imac.json` file.

## API v1

All API endpoints are available under `/api/v1`:

- `GET /files?path=Yavor/Courses` — list a directory.
- `GET /folders?path=Yavor` — list child directories.
- `GET /search?q=history` — search file names, paths, and keywords.
- `GET /stream?path=Yavor/Courses/audio.mp3` — stream a media file.
- `GET /media/Yavor/Courses/audio.mp3/stream` — path-based streaming endpoint.

Streaming supports `GET`, `HEAD`, `Accept-Ranges: bytes`, and `206 Partial Content`. Paths are restricted to the configured media root.

## Project structure

```text
cmd/gomediahomeserver/   Go server and embedded web admin
ios/                     iOS client project and API notes
android/                 Android client project notes
chrome-extension/        Separate Chrome downloader extension versions
config.example.json      Example server configuration
config.imac.example.json  Example LAN configuration for an iMac server
```

## Development status

This project is intended for local development and private LAN use. Authentication, user accounts, and production service management should be added before exposing the server outside the trusted network.

## Client configuration

The iOS app, Android app, and Chrome plugin use a placeholder LAN address by default:

```text
http://YOUR-IMAC-IP:8095/api/v1
```

Set the real iMac address in the client Settings or Chrome plugin options. The real
machine-specific configuration is intentionally excluded from Git.

## GitHub preflight

Before the first push, verify the local checks:

```sh
go test ./...
python3 -m py_compile chrome-extension/vimeo-downloader-v2/bridge.py
cd android && ./gradlew --no-daemon :app:assembleDebug
```

GitHub Actions runs the Go, Android, and Chrome plugin checks on every push and pull request.

## LAN and production deployment

The server binds to the configured host and port. Use `0.0.0.0` only on a trusted
LAN, protect port `8095` with the operating system firewall, and do not expose the
server directly to the public Internet. Authentication and TLS are not included yet.

### macOS launchd service

The recommended installation uses the included installer:

```sh
chmod +x deploy/install-macos-launchd.sh
./deploy/install-macos-launchd.sh
```

The installer builds the binary if needed, creates a per-user LaunchAgent, and
configures `RunAtLoad` and `KeepAlive`. Inspect or remove it with:

```sh
launchctl print "gui/$(id -u)/com.gomediahomeserver"
tail -f data/server.stdout.log
./deploy/uninstall-macos-launchd.sh
```

The service runs as the logged-in user, which keeps access to a user-owned media
folder simple. It starts after login and restarts after an unexpected exit.

### Linux systemd service

Run the included installer from the repository root:

```sh
chmod +x deploy/install-linux-systemd.sh
./deploy/install-linux-systemd.sh
systemctl status gomediahomeserver
```

### Windows service

Build with `go build -buildvcs=false -o gomediahomeserver.exe ./cmd/gomediahomeserver`, place the
binary and `config.json` in a protected directory, and register it with a service
manager such as NSSM or WinSW. Configure the service working directory to the
directory containing `config.json`, then allow inbound TCP `8095` in Windows
Firewall only for the private LAN profile.

With NSSM, the service values are:

```text
Application:       C:\goMediaHomeServer\gomediahomeserver.exe
Startup directory: C:\goMediaHomeServer
Arguments:         (none)
Service name:      goMediaHomeServer
```

Set the service startup type to **Automatic**, then use `nssm start goMediaHomeServer`.

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE).
