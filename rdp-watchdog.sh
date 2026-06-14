#!/bin/sh
set -eu

SUSPENDED=0
FF_PIDFILE="/tmp/firefox.pid"
LOG="/tmp/watchdog.log"
DEBOUNCE=1
LOG_MAX=1048576
ROTATE_INTERVAL=300
ROTATE_COUNT=0

echo "watchdog started" > "$LOG"

while true; do
    ROTATE_COUNT=$((ROTATE_COUNT + 1))
    if [ "$ROTATE_COUNT" -ge "$ROTATE_INTERVAL" ]; then
        if [ -f "$LOG" ] && [ "$(wc -c < "$LOG" 2>/dev/null || echo 0)" -gt "$LOG_MAX" ]; then
            tail -c "$LOG_MAX" "$LOG" > "${LOG}.tmp" 2>/dev/null && mv "${LOG}.tmp" "$LOG"
        fi
        ROTATE_COUNT=0
    fi

    if ss -tn state established 2>/dev/null | grep -q ':3389 '; then
        if [ "$SUSPENDED" -eq 1 ]; then
            sleep "$DEBOUNCE"
            if ss -tn state established 2>/dev/null | grep -q ':3389 '; then
                echo "$(date) CONNECTED -> resume Firefox" >> "$LOG"
                kill -CONT "$(cat "$FF_PIDFILE")" 2>/dev/null || true
                SUSPENDED=0
            fi
        fi
    else
        if [ "$SUSPENDED" -eq 0 ]; then
            sleep "$DEBOUNCE"
            if ! ss -tn state established 2>/dev/null | grep -q ':3389 '; then
                echo "$(date) DISCONNECTED -> freeze Firefox" >> "$LOG"
                kill -STOP "$(cat "$FF_PIDFILE")" 2>/dev/null || true
                SUSPENDED=1
            fi
        fi
    fi
    sleep 2
done
