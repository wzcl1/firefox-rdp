# Firefox over RDP

Lightweight Debian-based Docker container that runs Firefox inside an Openbox window manager, accessible via RDP.

Useful for:
- Running a browser remotely without a full desktop environment
- Isolated browsing sessions
- Kiosk-style browser deployments

## Quick Start

```sh
git clone https://github.com/wzcl1/firefox-rdp.git
cd firefox-rdp
docker compose up -d
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
- **uBlock Origin** — pre-installed via Firefox Enterprise Policies (auto-downloads on first launch)
- **Performance tuned** — GPU features disabled, content processes limited, cached optimized for container/RDP use
- **Minimal footprint** — stripped of crash reporter, updater, PNG sender, GNOME icons, docs, and other unnecessary files
- **Openbox window manager** — lightweight, just enough to give Firefox proper window decorations

## Configuration

Environment variables in `docker-compose.yml`:

| Variable            | Default         | Description                            |
|---------------------|-----------------|----------------------------------------|
| `RDP_USER`          | `browser`       | Linux/RDP username                    |
| `RDP_PASSWORD`      | `change-me`     | Linux/RDP password                    |
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
      - "4000:3389"
    environment:
      RDP_PASSWORD: secure-password-here
      FIREFOX_START_URL: https://example.com
      FIREFOX_ARGS: --kiosk
    shm_size: "2gb"
    restart: unless-stopped
```

## Security

- Change the default password before exposing beyond localhost
- xrdp uses password-based login — put it behind a VPN, SSH tunnel, or trusted private network for real deployments
- The container runs with `--shm-size=2gb` to prevent browser crashes from Docker's small default shared memory

## Building from source

```sh
docker compose up --build -d
```

Or using `docker run` directly:

```sh
docker run --rm -p 3389:3389 \
  -e RDP_PASSWORD='use-a-real-password' \
  -e FIREFOX_START_URL='https://example.com' \
  --shm-size=1g \
  firefox-rdp:latest
```

## How it works

1. The container starts xrdp (X Remote Desktop Protocol server)
2. On RDP connection, it launches Openbox as the window manager
3. Firefox starts inside the Openbox session with a pre-configured profile
4. Firefox Enterprise Policies (`policies.json`) auto-install uBlock Origin and apply performance tuning
5. Firefox `user.js` applies container-optimized about:config preferences (WebGL disabled, limited content processes, memory cache tuned, accessibility disabled)
