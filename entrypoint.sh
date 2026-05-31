#!/bin/sh
set -eu

user="${RDP_USER:-browser}"
password="${RDP_PASSWORD:-browser}"
uid="${RDP_UID:-1000}"
gid="${RDP_GID:-1000}"

if ! getent group "$user" >/dev/null 2>&1; then
    groupadd -g "$gid" "$user"
fi

if ! id "$user" >/dev/null 2>&1; then
    useradd -m -u "$uid" -g "$user" -s /bin/bash "$user"
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

/usr/sbin/xrdp-sesman --nodaemon &
exec /usr/sbin/xrdp --nodaemon
