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
- **uBlock Origin** — downloaded from GitHub releases at build time (latest version via API), bundled in the image. Firefox verifies Mozilla's signature at install time — no manual SHA256 needed. Other extensions can still be installed manually.
- **Performance tuned** — Firefox Enterprise Policies plus `user.js` disable background services, speculation, telemetry, and crypto overhead to minimise CPU use in the container.
- **Privacy first** — built-in tracking protection intentionally disabled (uBlock covers it) to avoid the dual-layer CPU cost; ETP, Pocket, telemetry, and account sync are all off.
- **Minimal footprint** — stripped of crash reporter, updater, pingsender, GNOME icons, docs, and other unnecessary files
- **RDP disconnect sleep** — when you disconnect from RDP, Firefox is frozen (SIGSTOP) to use zero CPU. On reconnect, it resumes instantly with full session state preserved.
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
| `FIREFOX_PROCESSES` | auto-detect     | Override `dom.ipc.processCount` (default: scaled by RAM) |
| `FIREFOX_CACHE_MB`  | auto-detect     | Override `browser.cache.memory.capacity` in MB (default: scaled by RAM) |

> **Security note:** `RDP_PASSWORD` is passed as a Docker environment variable, which means it's visible via `docker inspect <container>` and in process listings on the host. Avoid running this alongside untrusted workloads. For production use, consider mounting the password as a file secret or using Docker secrets instead of a plain environment variable.

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

## Performance & Privacy Tuning

The container applies two layers of Firefox configuration. The primary goal is **minimising CPU usage** for a single-user RDP session in a constrained container. Privacy and clean-state behaviour are secondary benefits.

### Firefox Enterprise Policies (`/opt/firefox/distribution/policies.json`)

Applied at startup, locked so the user cannot override them. The JSON is embedded inline in the Dockerfile (no extra file/layer).

| Group | Settings | Reason |
|-------|----------|--------|
| **Telemetry & accounts** | `DisableTelemetry`, `DisableFirefoxStudies`, `DisableFeedbackCommands`, `DisableFirefoxAccounts`, `DisableSystemAddonUpdate`, `DisableDeveloperTools` | Eliminates background reporting, A/B experiments, and dev-tools overhead. Accounts disabled because there's no use for sync in a single-session container. |
| **Auto-updates** | `AppAutoUpdate`, `BackgroundAppUpdate`, `ExtensionUpdate` = `false` | Updates happen at Docker image build time, never at runtime. Stops periodic update-check network calls. |
| **Tracking & content** | `EnableTrackingProtection: false` (locked), `FirefoxHome.*` (all off, locked), `Homepage` = `about:blank` (locked), `SearchSuggestEnabled`, `FirefoxSuggest.*`, `VisualSearchEnabled` = `false` | uBlock Origin is force-installed and covers ad/tracking filtering; running ETP on top duplicates that CPU work. Disabling Firefox Home and Suggest eliminates background feeds. |
| **New Tab & search** | `NoDefaultBookmarks`, `OverrideFirstRunPage` / `OverridePostUpdatePage` = `""` | Clean profile, no marketing/onboarding pages. |
| **Extensions** | `uBlock0@raymondhill.net` = `force_installed` from local `.xpi` | uBlock Origin is bundled in the image (downloaded from GitHub at build time) and locked. Firefox verifies Mozilla's addon signature at install time — no manual SHA256 needed. Other extensions can still be installed manually from AMO or as local `.xpi` files (including temporary installs via `about:debugging`). |
| **Network** | `DNSOverHTTPS` = `true` (locked), `PostQuantumKeyAgreementEnabled` = `false`, `DisableEncryptedClientHello` = `false` | DNS-over-HTTPS is enabled for encrypted, privacy-preserving resolution. Post-quantum key agreement is off to reduce per-connection CPU cost. Encrypted Client Hello is left at its default (not disabled). |
| **Disabled APIs** | `TranslateEnabled`, `XSLTEnabled`, `PictureInPicture` (locked), `PrintingEnabled` = `false` | Translation, XSLT transforms, and print preview rendering are heavy. PiP would spin up an extra video-decode pipeline. |
| **Browser cleanup** | `DisableFormHistory`, `PasswordManagerEnabled`, `OfferToSaveLogins` = `false` | No password manager; form history disabled. `SanitizeOnShutdown` was removed so the Firefox profile persists across RDP disconnect/reconnect and container restarts. |
| **Misc hardening** | `SkipTermsOfUse`, `DontCheckDefaultBrowser`, `DisableSetDesktopBackground`, `DisableBuiltinPDFViewer` = `false`, `GoToIntranetSiteForSingleWordEntryInAddressBar` = `false`, `IPProtectionAvailable` = `false` | Skips onboarding dialogs and silent connections. PDF viewer left enabled — its CPU cost is bounded to active viewing (idle tabs do nothing). |

The full policy is in `Dockerfile:46` (single-line JSON written via `printf`).

### `user.js` Profile Preferences (written by `rdp-session.sh`)

The `user.js` is regenerated on every session start so updates take effect. It complements the policy layer with about:config tweaks Firefox doesn't expose via policies.

| Category | Prefs | Reason |
|----------|-------|--------|
| **GPU & media** | `gfx.webrender.enabled`, `media.hardware-video-decoding.enabled`, `media.ffmpeg.vaapi.enabled`, `layers.acceleration.disabled`, `webgl.disabled`, `gfx.canvas.accelerated` = all off | No GPU in container. WebRender / hardware video decode / canvas acceleration would either fail or force a CPU fallback path. |
| **Animation** | `general.smoothScroll` = `false`, `layout.animation.prefers-reduced-motion` = `1`, `image.animation_mode` = `"none"` | Disables smooth scrolling, CSS animations, and animated GIFs to eliminate per-frame repaint CPU cost. |
| **Font cache** | `gfx.content.skia-font-cache-size` = `5` | Reduces Skia font cache from 16MB to 5MB to lower memory footprint. |
| **Process model** | `dom.ipc.processCount` scaled by available RAM | Auto-detects cgroup memory limit (or falls back to `/proc/meminfo`) and sets process count: <1 GB→1, 1–2 GB→2, 2–4 GB→4, 4–8 GB→6, ≥8 GB→8. Override via `FIREFOX_PROCESSES` env var. |
| **Cache** | `browser.cache.disk.enable` = `false`, `browser.cache.disk.capacity` = 100MB, `browser.cache.memory.enable` = `true`, `browser.cache.memory.capacity` scaled by RAM | Memory cache scales with available RAM: <1 GB→32MB, 1–2 GB→64MB, 2–4 GB→128MB, 4–8 GB→256MB, ≥8 GB→512MB. Override via `FIREFOX_CACHE_MB` env var. Firefox profile and cache persist across restarts via a named Docker volume. |
| **Session restore** | `browser.sessionhistory.max_entries` = 10, `browser.sessionstore.max_tabs_undo` = 0, `browser.sessionstore.privacy_level` = 2, `browser.sessionstore.interval` = 30s | Bounded back/forward list; no recently-closed-tabs undo (per-tab snapshots are expensive). |
| **Network prediction** | `network.predictor.enabled` = `false`, `network.prefetch-next` = `false`, `network.dns.disablePrefetch` = `true`, `network.dns.disablePrefetchFromHTTPS` = `true`, `network.http.speculative-parallel-limit` = 0, `browser.places.speculativeConnect.enabled` = `false`, `browser.urlbar.speculativeConnect.enabled` = `false` | Kills all background pre-connection / pre-resolution work. |
| **Connection limits** | `network.http.max-connections` = 48, `network.http.max-persistent-connections-per-server` = 6, `network.dnsCacheEntries` = 256, `network.ssl_tokens_cache_capacity` = 1000 | Lower total connection count (Firefox default is 6 per server) and reduced TLS session cache to bound resource usage. |
| **Network performance** | `network.http.pipelining` = `true`, `network.http.proxy.pipelining` = `true` | Enables HTTP pipelining for better throughput on high-latency links. |
| **TLS** | `security.ssl.enable_ocsp_stapling` = `false` | Disables OCSP stapling to avoid extra round-trips and CPU cost per TLS handshake. |
| **Background services** | `network.captive-portal-service.enabled`, `network.connectivity-service.enabled`, `browser.casting.enabled`, `media.gmp-gmpopenh264.enabled`, `app.update.enabled` = `false`, `extensions.getAddons.cache.enabled`, `lightweightThemes.update.enabled` = `false`, `browser.topsites.contile.enabled` = `false` | Stops periodic HTTP probes, mDNS cast discovery, OpenH264 download, and add-on metadata fetches that fire in the background. |
| **Tab & memory pressure** | `browser.tabs.unloadOnLowMemory` = `true`, `browser.low_commit_space_threshold_mb` = 256, `browser.pagethumbnails.capturing_disabled` = `true`, `browser.newtabpage.activity-stream.enabled` = `false` | Drops tabs under memory pressure; disables off-screen thumbnail rendering and activity-stream feeds. |
| **Media & content** | `media.autoplay.default` = 5, `media.video_stats.enabled` = `false`, `gfx.font_rendering.opentype_svg.enabled` = `false`, `javascript.options.asmjs` = `false`, `camera.control.face_detection.enabled` = `false` | Blocks autoplay video decode; removes per-frame and per-glyph CPU overhead from features we don't use. |
| **UI noise** | `browser.startup.homepage_override.mstone` = `ignore`, `browser.startup.blankWindow` = `false`, `accessibility.force_disabled` = 1, `clipboard.autocopy` = `false` | Suppresses the blank-window flash during startup, the accessibility walker, and Linux selection autocopy. |
| **Telemetry** | `app.normandy.enabled`, `app.shield.optoutstudies.enabled`, `browser.newtabpage.activity-stream.feeds.telemetry`, `browser.newtabpage.activity-stream.telemetry`, `browser.ping-centre.telemetry`, `toolkit.telemetry.unified`, `datareporting.healthreport.uploadEnabled` = `false`; `toolkit.coverage.opt-out` = `true`; `browser.contentblocking.report.endpoint_url` = `""` | Disables all telemetry, Shield experiments, health reporting, and content-blocking reporting to eliminate background network calls and CPU overhead. |

The full `user.js` is in `rdp-session.sh:41-106`.

## RDP Disconnect Sleep

When you disconnect from RDP (close the client, network drop, etc.), a watchdog process detects the TCP disconnection and sends `SIGSTOP` to Firefox. This completely freezes the process — zero CPU usage, zero network activity, while keeping the full session state in memory.

When you reconnect, the watchdog detects the new TCP connection and sends `SIGCONT` to resume Firefox exactly where you left it.

| Behaviour | Detail |
|-----------|--------|
| Detection | Polls `ss -tn state established | grep ':3389 '` every 2 seconds |
| Debounce | 1-second confirmation delay before acting on state change, preventing thrashing from connection flaps |
| Freeze | `SIGSTOP` — process suspended by kernel, zero CPU |
| Thaw | `SIGCONT` — process resumes instantly |
| Memory | Stays in RAM (not swapped to disk) |
| Log | Bounded to 1MB with automatic rotation |
| Profile | Persists across disconnect/reconnect and container restart via Docker volume |

This is transparent to the user — connect, browse, disconnect, reconnect, and your tabs are exactly where you left them.

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

### Privilege model

The container uses a layered approach to minimise the root attack surface:

| Process | User | Why |
|---------|------|-----|
| `xrdp` | root (unavoidable) | Must create virtual X11 displays, manage session lifecycle |
| `xrdp-sesman` | root (unavoidable) | Spawns session processes as the authenticated user |
| `rdp-watchdog` | `RDP_USER` | Only signals Firefox; root privileges dropped after startup |
| Firefox + Openbox | `RDP_USER` | Runs fully unprivileged inside the RDP session |

Additional hardening in `docker-compose.yml`:

- **`cap_drop: [ALL]`** — all Linux capabilities are dropped, then only `NET_BIND_SERVICE`, `SETUID`, and `DAC_READ_SEARCH` are restored (minimum required for xrdp)
- **`read_only: true`** — the root filesystem is read-only; only `/tmp`, `/var`, `/run`, and the user's home directories are writable via tmpfs mounts
- **`tmpfs` mounts** — `/tmp`, `/var`, `/run` are in-memory filesystems with bounded sizes
- **Named volume** — `/home/browser` (Firefox profile, extensions, bookmarks) is stored in the `firefox-profile` Docker volume, persisting across container restarts and only destroyed when the volume is explicitly removed

For defense-in-depth, avoid exposing port 3389 directly — use an SSH tunnel or Tailscale sidecar.

### Health check

The Dockerfile includes a `HEALTHCHECK` that verifies xrdp is listening on port 3389 every 30 seconds. This allows Docker and orchestrators to detect a broken container and restart it automatically.

| Parameter | Value |
|-----------|-------|
| Interval | 30 seconds |
| Timeout | 5 seconds |
| Start period | 10 seconds |
| Retries | 3 |

### Extension surface

uBlock Origin is force-installed and cannot be removed. The `.xpi` is downloaded from GitHub at build time (latest version via API) and bundled in the image. Firefox verifies Mozilla's addon signature at install time — no manual SHA256 verification needed. Other extensions can be installed from AMO or as local `.xpi` files (including temporary installs via `about:debugging`).

## How it works

1. The container starts xrdp (X Remote Desktop Protocol server), xrdp-sesman, and a background watchdog process
2. The watchdog runs as the unprivileged `RDP_USER` and monitors the RDP TCP connection every 2 seconds, with a 1-second debounce to prevent rapid state changes
3. On RDP connection, it launches Openbox as the window manager and Firefox with a pre-configured profile
4. When the client disconnects, the watchdog sends `SIGSTOP` to Firefox (zero CPU, stays in RAM). On reconnect, it sends `SIGCONT` to resume instantly
5. Firefox Enterprise Policies (`policies.json`) force-install uBlock Origin from the bundled `.xpi` (Mozilla's signature is verified at install time), lock the Firefox Home page to `about:blank`, disable telemetry/updates/PiP, and enable DNS-over-HTTPS
6. Firefox `user.js` (regenerated each session) applies container-optimised about:config preferences: WebRender and hardware video decode off, GPU acceleration disabled, content processes capped at 2, all background services and speculative connections disabled
