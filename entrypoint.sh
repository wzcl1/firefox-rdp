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

id "$user" >/dev/null 2>&1 || { echo "ERROR: user $user does not exist" >&2; exit 1; }

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

# Run the watchdog as the unprivileged user — it only signals Firefox
# processes, which also run as $user, so root is not required.
su -s /bin/sh -c '/usr/local/bin/rdp-watchdog.sh &' "$user"

/usr/sbin/xrdp-sesman --nodaemon &
exec /usr/sbin/xrdp --nodaemon
