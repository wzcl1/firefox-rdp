#!/bin/sh
set -eu

export MOZ_ENABLE_WAYLAND=0
export NO_AT_BRIDGE=1
export XDG_RUNTIME_DIR="/tmp/runtime-${USER:-browser}"
export HOME="${HOME:-/home/${USER:-browser}}"

# Firefox performance tuning -- disable GPU features in container
export MOZ_WEBRENDER=0
export MOZ_GLX_TEST=0

mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

dbus-daemon --session --fork 2>/dev/null || true

# Ensure Firefox profile exists before launching
PROFILES_INI="${HOME}/.mozilla/firefox/profiles.ini"
PROFILE_DIR="${HOME}/.mozilla/firefox/default-release"

if [ ! -f "$PROFILES_INI" ]; then
    mkdir -p "$PROFILE_DIR"
    cat > "$PROFILES_INI" << 'EOF'
[General]
StartWithLastProfile=1

[Profile0]
Name=default-release
IsRelative=1
Path=default-release
Default=yes
EOF
fi

# Always write/overwrite user.js so pref changes take effect on update
mkdir -p "$PROFILE_DIR"
cat > "$PROFILE_DIR/user.js" << 'EOF'
// Performance tuning for container/RDP environment
user_pref("gfx.webrender.enabled", false);
user_pref("media.hardware-video-decoding.enabled", false);
user_pref("media.ffmpeg.vaapi.enabled", false);
user_pref("webgl.disabled", true);
user_pref("layers.acceleration.disabled", true);
user_pref("dom.ipc.processCount", 2);
user_pref("browser.sessionhistory.max_entries", 50);
user_pref("browser.sessionstore.interval", 30000);
user_pref("browser.sessionstore.max_tabs_undo", 10);
user_pref("browser.sessionstore.max_windows_undo", 3);
user_pref("browser.cache.disk.capacity", 102400);
user_pref("browser.cache.disk.enable", false);
user_pref("browser.cache.memory.enable", true);
user_pref("browser.cache.memory.capacity", 32768);
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("network.http.max-connections", 64);
user_pref("network.http.max-persistent-connections-per-server", 8);
user_pref("network.dnsCacheEntries", 256);
user_pref("network.prefetch-next", false);
user_pref("browser.places.speculativeConnect.enabled", false);
user_pref("accessibility.force_disabled", 1);
user_pref("browser.tabs.unloadOnLowMemory", true);
user_pref("browser.low_commit_space_threshold_mb", 256);
EOF

openbox &
wm_pid="$!"

cleanup() {
    kill "$wm_pid" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

# Wait for X server and window manager to be ready
for i in $(seq 1 10); do
    xdpyinfo >/dev/null 2>&1 && break
    sleep 0.5
done

exec firefox --no-remote --new-instance --profile "$PROFILE_DIR" ${FIREFOX_ARGS:-} "${FIREFOX_START_URL:-about:blank}"
