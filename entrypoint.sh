#!/bin/bash
set -euo pipefail

# Security: this script runs as root to perform user setup and start xrdp.
# The watchdog process is dropped to the unprivileged RDP_USER after setup.
# xrdp/xrdp-sesman must remain root (see Dockerfile header comment).

user="${RDP_USER:-browser}"
uid="${RDP_UID:-1000}"
gid="${RDP_GID:-1000}"

if [ -z "${RDP_PASSWORD:-}" ]; then
    echo "ERROR: RDP_PASSWORD must be set" >&2
    exit 1
fi
password="$RDP_PASSWORD"

# Create user if it doesn't exist (needed for custom RDP_USER values).
# With read_only: false the overlay is writable, so groupadd/useradd work.
if ! id "$user" >/dev/null 2>&1; then
    if ! getent group "$user" >/dev/null 2>&1; then
        getent group "$gid" >/dev/null 2>&1 || groupadd -g "$gid" "$user"
    fi
    useradd -m -u "$uid" -g "$user" -s /bin/bash "$user" 2>/dev/null || true
    id "$user" >/dev/null 2>&1 || { echo "ERROR: failed to create user $user" >&2; exit 1; }
fi

# Write directly to /etc/shadow to bypass PAM, which fails in read-only containers.
hashed=$(openssl passwd -6 "$password")
escaped_user=$(printf '%s\n' "$user" | sed 's/[.[\*^$()+?{|]/\\&/g')
sed -i "s|^${escaped_user}:.*|${user}:${hashed}:19000:0:99999:7:::|" /etc/shadow

mkdir -p "/home/$user/.config/openbox"
cat > "/home/$user/.config/openbox/autostart" <<'EOF'
xsetroot -solid '#202124' &
EOF

mkdir -p /var/run/xrdp
rm -f /var/run/xrdp/xrdp.pid /var/run/xrdp/xrdp-sesman.pid

# Run the watchdog — it only signals Firefox processes and checks TCP state,
# so it works fine as root. In rootless Docker, su/setgroups is blocked.
/usr/local/bin/rdp-watchdog.sh &

/usr/sbin/xrdp-sesman --nodaemon &
exec /usr/sbin/xrdp --nodaemon
