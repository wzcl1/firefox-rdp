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
- **uBlock Origin** — force-installed from AMO (Mozilla Add-ons) via Firefox Enterprise Policies. Always gets the latest version on first launch; Mozilla's signature verification ensures integrity. Other extensions can still be installed manually.
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
| **Extensions** | `uBlock0@raymondhill.net` = `force_installed` from AMO | uBlock Origin is downloaded from addons.mozilla.org on first launch and locked. Mozilla's signing verifies integrity. Other extensions can still be installed manually from AMO or as local `.xpi` files (including temporary installs via `about:debugging`). |
| **Network** | `NetworkPrediction`, `DNSOverHTTPS` (locked), `PostQuantumKeyAgreementEnabled` = `false`, `DisableEncryptedClientHello` = `true` | Disables DNS-over-HTTPS (extra TLS per lookup), predictive networking, post-quantum key agreement, and ECH — all measurable per-connection CPU costs. The RDP tunnel already encrypts the transport. |
| **Disabled APIs** | `TranslateEnabled`, `XSLTEnabled`, `PictureInPicture` (locked), `PrintingEnabled` = `false` | Translation, XSLT transforms, and print preview rendering are heavy. PiP would spin up an extra video-decode pipeline. |
| **Browser cleanup** | `DisableFormHistory`, `PasswordManagerEnabled`, `OfferToSaveLogins` = `false` | No password manager; form history disabled. `SanitizeOnShutdown` was removed so the Firefox profile persists across RDP disconnect/reconnect and container restarts. |
| **Misc hardening** | `SkipTermsOfUse`, `DontCheckDefaultBrowser`, `DisableSetDesktopBackground`, `DisableBuiltinPDFViewer` = `false`, `GoToIntranetSiteForSingleWordEntryInAddressBar` = `false`, `IPProtectionAvailable` = `false` | Skips onboarding dialogs and silent connections. PDF viewer left enabled — its CPU cost is bounded to active viewing (idle tabs do nothing). |

The full policy is in `Dockerfile:46` (single-line JSON written via `printf`).

### `user.js` Profile Preferences (written by `rdp-session.sh`)

The `user.js` is regenerated on every session start so updates take effect. It complements the policy layer with about:config tweaks Firefox doesn't expose via policies.

| Category | Prefs | Reason |
|----------|-------|--------|
| **GPU & media** | `gfx.webrender.enabled`, `media.hardware-video-decoding.enabled`, `media.ffmpeg.vaapi.enabled`, `layers.acceleration.disabled`, `webgl.disabled` = all off | No GPU in container. WebRender / hardware video decode would either fail or force a CPU fallback path. |
| **Process model** | `dom.ipc.processCount` = `2` | Caps content processes to 2 to fit in low-memory containers. |
| **Cache** | `browser.cache.disk.enable` = `false`, `browser.cache.disk.capacity` = 100MB, `browser.cache.memory.enable` = `true`, `browser.cache.memory.capacity` = 32MB | Disk cache is unnecessary (profile is wiped on shutdown). Memory cache is bounded to keep the container footprint small. |
| **Session restore** | `browser.sessionhistory.max_entries` = 10, `browser.sessionstore.max_tabs_undo` = 0, `browser.sessionstore.privacy_level` = 2, `browser.sessionstore.interval` = 30s | Bounded back/forward list; no recently-closed-tabs undo (per-tab snapshots are expensive). |
| **Network prediction** | `network.predictor.enabled` = `false`, `network.prefetch-next` = `false`, `network.dns.disablePrefetch` = `true`, `network.dns.disablePrefetchFromHTTPS` = `true`, `network.http.speculative-parallel-limit` = 0, `browser.places.speculativeConnect.enabled` = `false`, `browser.urlbar.speculativeConnect.enabled` = `false` | Kills all background pre-connection / pre-resolution work. |
| **Background services** | `network.captive-portal-service.enabled`, `network.connectivity-service.enabled`, `browser.casting.enabled`, `media.gmp-gmpopenh264.enabled`, `app.update.enabled` = `false`, `extensions.getAddons.cache.enabled`, `lightweightThemes.update.enabled` = `false`, `browser.topsites.contile.enabled` = `false` | Stops periodic HTTP probes, mDNS cast discovery, OpenH264 download, and add-on metadata fetches that fire in the background. |
| **Tab & memory pressure** | `browser.tabs.unloadOnLowMemory` = `true`, `browser.low_commit_space_threshold_mb` = 256, `browser.pagethumbnails.capturing_disabled` = `true`, `browser.newtabpage.activity-stream.enabled` = `false` | Drops tabs under memory pressure; disables off-screen thumbnail rendering and activity-stream feeds. |
| **Media & content** | `media.autoplay.default` = 5, `media.video_stats.enabled` = `false`, `gfx.font_rendering.opentype_svg.enabled` = `false`, `javascript.options.asmjs` = `false`, `camera.control.face_detection.enabled` = `false` | Blocks autoplay video decode; removes per-frame and per-glyph CPU overhead from features we don't use. |
| **UI noise** | `browser.startup.homepage_override.mstone` = `ignore`, `browser.startup.blankWindow` = `false`, `accessibility.force_disabled` = 1, `clipboard.autocopy` = `false` | Suppresses the blank-window flash during startup, the accessibility walker, and Linux selection autocopy. |
| **Connection limits** | `network.http.max-connections` = 64, `network.http.max-persistent-connections-per-server` = 6, `network.dnsCacheEntries` = 256 | Modest per-server limit (Firefox default is 6) and a small DNS cache to avoid unbounded growth. |

The full `user.js` is in `rdp-session.sh:38-87`.

## RDP Disconnect Sleep

When you disconnect from RDP (close the client, network drop, etc.), a watchdog process detects the TCP disconnection and sends `SIGSTOP` to Firefox. This completely freezes the process — zero CPU usage, zero network activity, while keeping the full session state in memory.

When you reconnect, the watchdog detects the new TCP connection and sends `SIGCONT` to resume Firefox exactly where you left it.

| Behaviour | Detail |
|-----------|--------|
| Detection | Polls `ss -tn 'sport = :3389'` every 2 seconds |
| Freeze | `SIGSTOP` — process suspended by kernel, zero CPU |
| Thaw | `SIGCONT` — process resumes instantly |
| Memory | Stays in RAM (not swapped to disk) |
| Profile | Persists across disconnect/reconnect; wiped only on container restart |

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
- **Privilege model:** The entrypoint runs as root to create system users and start xrdp/xrdp-sesman. Debian's xrdp packages drop privileges for session handling by default, so RDP sessions run as the unprivileged `RDP_USER`. For defense-in-depth, avoid exposing port 3389 directly — use an SSH tunnel or Tailscale sidecar.
- **Extension surface:** uBlock Origin is force-installed from AMO (Mozilla Add-ons) and cannot be removed. Firefox verifies Mozilla's signature on the `.xpi` at install time. Other extensions can be installed from AMO or as local `.xpi` files (including temporary installs via `about:debugging`).

## How it works

1. The container starts xrdp (X Remote Desktop Protocol server) and a background watchdog process
2. On RDP connection, it launches Openbox as the window manager
3. Firefox starts inside the Openbox session with a pre-configured profile
4. The watchdog monitors the RDP TCP connection on port 3389 every 2 seconds. When the client disconnects, it sends `SIGSTOP` to Firefox (zero CPU, stays in RAM). On reconnect, it sends `SIGCONT` to resume instantly.
5. Firefox Enterprise Policies (`policies.json`) force-install uBlock Origin from AMO (Mozilla verifies the signature), lock the Firefox Home page to `about:blank`, disable telemetry/updates/DoH/PiP
6. Firefox `user.js` (regenerated each session) applies container-optimised about:config preferences: WebRender and hardware video decode off, GPU acceleration disabled, content processes capped at 2, all background services and speculative connections disabled
