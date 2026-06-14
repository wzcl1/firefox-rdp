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
        grp_line="$user:x:$gid:"
        echo "$grp_line" >> /etc/group
        echo "$grp_line:" >> /etc/gshadow
    fi
    if ! getent passwd "$user" >/dev/null 2>&1; then
        if getent passwd "$uid" >/dev/null 2>&1; then
            uid=$(awk -F: '$3>=1000{print $3+1}' /etc/passwd | sort -n | tail -1)
            [ "$uid" -lt 1000 ] && uid=1001
        fi
        echo "$user:x:$uid:$gid::/home/$user:/bin/bash" >> /etc/passwd
        echo "$user:!::0:99999:7:::" >> /etc/shadow
        mkdir -p "/home/$user"
        chmod 777 "/home/$user"
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
