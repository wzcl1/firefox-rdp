#!/bin/bash
set -euo pipefail

# Security: this script runs as root to perform user setup and start xrdp.
# xrdp/xrdp-sesman must remain root (see Dockerfile header comment).
# The watchdog runs as root because su/setgroups is blocked in rootless Docker.

user="${RDP_USER:-browser}"
uid=1000
gid=1000

if [ -z "${RDP_PASSWORD:-}" ]; then
    echo "ERROR: RDP_PASSWORD must be set" >&2
    exit 1
fi
password="$RDP_PASSWORD"

# Create user if it doesn't exist (needed for custom RDP_USER values).
# Write directly to /etc files instead of using groupadd/useradd, which fail
# on overlay filesystems due to file locking (same reason we bypass PAM for shadow).
if ! id "$user" >/dev/null 2>&1; then
    # Find a free GID/UID if the requested ones are taken
    if getent group "$user" >/dev/null 2>&1; then
        grp_line=$(getent group "$user")
    else
        if getent group "$gid" >/dev/null 2>&1; then
            gid=$(awk -F: '{print $3+1}' /etc/group | sort -n | tail -1)
            [ "$gid" -lt 1000 ] && gid=1001
        fi
        echo "$user:x:$gid:" >> /etc/group
        echo "$user:!::" >> /etc/gshadow
    fi
    if ! getent passwd "$user" >/dev/null 2>&1; then
        if getent passwd "$uid" >/dev/null 2>&1; then
            uid=$(awk -F: '$3>=1000{print $3+1}' /etc/passwd | sort -n | tail -1)
            [ "$uid" -lt 1000 ] && uid=1001
        fi
        echo "$user:x:$uid:$gid::/home/$user:/bin/bash" >> /etc/passwd
        echo "$user:!::0:99999:7:::" >> /etc/shadow
        mkdir -p "/home/$user"
        chmod 755 "/home/$user" 2>/dev/null || true
    fi
    id "$user" >/dev/null 2>&1 || { echo "ERROR: failed to create user $user" >&2; exit 1; }
fi

# Override USER/HOME to prevent host env leaking into child processes.
# Without this, host USER=sash leaks in and rdp-session.sh uses /home/sash.
export USER="$user"
export HOME="/home/$user"

# Write directly to /etc/shadow to bypass PAM, which fails in read-only containers.
hashed=$(openssl passwd -6 "$password")
escaped_user=$(printf '%s\n' "$user" | sed 's/[.[\*^$()+?{|]/\\&/g')
sed -i "s|^${escaped_user}:.*|${user}:${hashed}:19000:0:99999:7:::|" /etc/shadow

mkdir -p "/home/$user/.config/openbox"
chmod 755 "/home/$user" "/home/$user/.config" "/home/$user/.config/openbox" 2>/dev/null || true
cat > "/home/$user/.config/openbox/autostart" <<'EOF'
xsetroot -solid '#202124' &
EOF

# Pre-create Firefox profile directory and profiles.ini.
# Firefox runs as the session user (browser) but the volume may have
# stale root-owned dirs from previous runs. Fix ownership here.
FF_PROFILE="/home/$user/.mozilla/firefox"
mkdir -p "$FF_PROFILE/default-release" 2>/dev/null || true
chmod -R 700 "/home/$user/.mozilla" 2>/dev/null || true
# profiles.ini tells Firefox where to find profiles
cat > "$FF_PROFILE/profiles.ini" 2>/dev/null <<PINI || true
[General]
StartWithLastProfile=1

[Profile0]
Name=default-release
IsRelative=1
Path=default-release
Default=1
PINI
chown -R "$(id -u "$user"):$(id -g "$user")" "/home/$user/.mozilla" 2>/dev/null || true

mkdir -p /var/run/xrdp /var/lib/dbus
[ -f /var/lib/dbus/machine-id ] || dbus-uuidgen > /var/lib/dbus/machine-id
rm -f /var/run/xrdp/xrdp.pid /var/run/xrdp/xrdp-sesman.pid

# Run the watchdog — it only signals Firefox processes and checks TCP state,
# so it works fine as root. In rootless Docker, su/setgroups is blocked.
/usr/local/bin/rdp-watchdog.sh &

/usr/sbin/xrdp-sesman --nodaemon &
exec /usr/sbin/xrdp --nodaemon
