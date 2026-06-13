#!/bin/sh
set -eu

SUSPENDED=0
LOG="/tmp/watchdog.log"

echo "watchdog started" > "$LOG"

while true; do
    if ss -tn state established 2>/dev/null | grep -q ':3389 '; then
        if [ "$SUSPENDED" -eq 1 ]; then
            echo "$(date) CONNECTED -> resume Firefox" >> "$LOG"
            pkill -CONT -f "firefox" 2>/dev/null || true
            SUSPENDED=0
        fi
    else
        if [ "$SUSPENDED" -eq 0 ]; then
            echo "$(date) DISCONNECTED -> freeze Firefox" >> "$LOG"
            pkill -STOP -f "firefox" 2>/dev/null || true
            SUSPENDED=1
        fi
    fi
    sleep 2
done
