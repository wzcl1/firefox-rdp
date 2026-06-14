#!/bin/bash
set -euo pipefail

# Security: this script runs as root to perform user setup and start xrdp.
# The watchdog process is dropped to the unprivileged RDP_USER after setup.
# xrdp/xrdp-sesman must remain root (see Dockerfile header comment).

user="${RDP_USER:-browser}"

if [ -z "${RDP_PASSWORD:-}" ]; then
    echo "ERROR: RDP_PASSWORD must be set" >&2
    exit 1
fi
password="$RDP_PASSWORD"
uid="${RDP_UID:-1000}"
gid="${RDP_GID:-1000}"

if ! getent group "$user" >/dev/null 2>&1; then
    for i in 1 2 3; do
        groupadd -g "$gid" "$user" 2>/dev/null && break
        sleep 0.5
    done
fi

if ! id "$user" >/dev/null 2>&1; then
    for i in 1 2 3; do
        useradd -m -u "$uid" -g "$user" -s /bin/bash "$user" 2>/dev/null && break
        sleep 0.5
    done
fi

echo "$user:$password" | chpasswd
install -d -m 700 -o "$user" -g "$user" "/home/$user/.config/openbox"

# Keep the session focused on Firefox while still giving xrdp a real window manager.
cat > "/home/$user/.config/openbox/autostart" <<'EOF'
xsetroot -solid '#202124' &
EOF
chown "$user:$user" "/home/$user/.config/openbox/autostart"

mkdir -p /var/run/xrdp
rm -f /var/run/xrdp/xrdp.pid /var/run/xrdp/xrdp-sesman.pid

# Run the watchdog as the unprivileged user — it only signals Firefox
# processes, which also run as $user, so root is not required.
su -s /bin/sh -c '/usr/local/bin/rdp-watchdog.sh &' "$user"

/usr/sbin/xrdp-sesman --nodaemon &
exec /usr/sbin/xrdp --nodaemon
