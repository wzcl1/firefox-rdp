#!/bin/sh
# Watchdog: freeze Firefox when RDP client disconnects, thaw on reconnect.
# Runs as root. Polls TCP connection on port 3389 every 2 seconds.
set -eu

SUSPENDED=0

while true; do
    if ss -tn 'sport = :3389' 2>/dev/null | grep -q ESTAB; then
        if [ "$SUSPENDED" -eq 1 ]; then
            pkill -CONT -f "firefox" 2>/dev/null || true
            SUSPENDED=0
        fi
    else
        if [ "$SUSPENDED" -eq 0 ]; then
            pkill -STOP -f "firefox" 2>/dev/null || true
            SUSPENDED=1
        fi
    fi
    sleep 2
done
