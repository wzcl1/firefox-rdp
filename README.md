# ⚠️⚠️ Warning ⚠️⚠️
AI-Generated Code Warning: This code was written by AI and has not been thoroughly tested. Use at your own risk. Review and test thoroughly before production use.

# Firefox over RDP

Lightweight Docker container that runs Firefox inside an Openbox window manager, accessible via RDP.

Supports both **amd64** and **arm64** architectures (auto-detected at build time).

Useful for:
- Running a browser remotely without a full desktop environment
- Isolated browsing sessions
- Kiosk-style browser deployments

## Quick Start

```sh
git clone https://github.com/wzcl1/firefox-rdp.git
cd firefox-rdp
docker compose up --build -d
```

Connect with any RDP client:

| Setting    | Value        |
|------------|--------------|
| Host       | `localhost`  |
| Port       | `4000`       |
| Username   | `browser`    |
| Password   | `change-me`  |

## Features

- **Latest Firefox** — downloads the latest stable release from Mozilla at build time
- **Multi-arch** — amd64 and arm64 auto-detected; correct Firefox binary downloaded per architecture
- **uBlock Origin** — pre-installed and locked via Firefox Enterprise Policies (`force_installed` with SHA256 verification)
- **Performance tuned** — GPU features disabled, content processes limited, cache optimized for container/RDP use
- **Minimal footprint** — stripped of crash reporter, updater, pingsender, GNOME icons, docs, and other unnecessary files
- **Openbox window manager** — lightweight, just enough to give Firefox proper window decorations

## Configuration

Environment variables in `docker-compose.yml`:

| Variable            | Default         | Description                            |
|---------------------|-----------------|----------------------------------------|
| `RDP_USER`          | `browser`       | Linux/RDP username                    |
| `RDP_PASSWORD`      | *(required)*    | Linux/RDP password (no default — must be set) |
| `RDP_UID`           | `1000`          | Linux UID for the user                |
| `RDP_GID`           | `1000`          | Linux GID for the user                |
| `FIREFOX_START_URL` | `about:blank`   | URL opened when the RDP session starts|
| `FIREFOX_ARGS`      | `""`            | Extra Firefox CLI arguments           |

### Example with custom options

```yaml
services:
  firefox-rdp:
    build: .
    ports:
      # Only listen on localhost — remove 127.0.0.1 to expose on all interfaces
      - "127.0.0.1:4000:3389"
    environment:
      RDP_PASSWORD: secure-password-here
      FIREFOX_START_URL: https://example.com
      FIREFOX_ARGS: --kiosk
    shm_size: "2gb"
    restart: unless-stopped
```

## Building from source

```sh
docker compose up --build -d
```

Docker BuildKit automatically provides `TARGETARCH` during the build. The `Dockerfile` uses it to select the correct Firefox download URL (`linux64` for amd64, `linux64-aarch64` for arm64).

## Architecture support

| Architecture | Firefox binary                        | Status |
|--------------|---------------------------------------|--------|
| amd64        | `linux64` (official Mozilla build)    | Tested |
| arm64        | `linux64-aarch64` (official Mozilla build) | Tested |

No `image` tag is set in `docker-compose.yml` — the image is always built locally for your architecture.

## Security

- `RDP_PASSWORD` is required — the container will refuse to start if not set
- xrdp uses password-based login — put it behind a VPN, SSH tunnel, or trusted private network for real deployments
- The container runs with `--shm-size=2gb` to prevent browser crashes from Docker's small default shared memory
- **Privilege model:** The entrypoint runs as root to create system users and start xrdp/xrdp-sesman. Debian's xrdp packages drop privileges for session handling by default, so RDP sessions run as the unprivileged `RDP_USER`. For defense-in-depth, avoid exposing port 3389 directly — use an SSH tunnel or Tailscale sidecar.

## How it works

1. The container starts xrdp (X Remote Desktop Protocol server)
2. On RDP connection, it launches Openbox as the window manager
3. Firefox starts inside the Openbox session with a pre-configured profile
4. Firefox Enterprise Policies (`policies.json`) auto-install uBlock Origin and apply performance tuning
5. Firefox `user.js` applies container-optimized about:config preferences (WebGL disabled, limited content processes, memory cache tuned, accessibility disabled)
