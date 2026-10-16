#!/bin/bash

# Every run is appended to a log file (kept at the last LOG_MAX_LINES lines) so
# that runs triggered by the session autostart can be debugged afterwards.
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/screen-layout-select"
LOG_FILE="$LOG_DIR/screen-layout-select.log"
LOG_MAX_LINES=2000

mkdir -p "$LOG_DIR"
if [[ -f $LOG_FILE ]] && (( $(wc -l < "$LOG_FILE") > LOG_MAX_LINES )); then
    tail -n "$LOG_MAX_LINES" "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
fi
exec > >(while IFS= read -r line; do printf '%s %s\n' "$(date '+%F %T')" "$line"; done | tee -a "$LOG_FILE") 2>&1

echo "===== Run started (pid $$, parent: $(ps -o comm= -p $PPID)) ====="
echo "Session: XDG_SESSION_TYPE=$XDG_SESSION_TYPE DISPLAY=$DISPLAY WAYLAND_DISPLAY=$WAYLAND_DISPLAY XAUTHORITY=$XAUTHORITY"
echo "Uptime: $(cut -d' ' -f1 /proc/uptime)s"

# Gets the IPv4 of the first connected wired interface. Wi-Fi is ignored since
# it doesn't imply a fixed location; virtual interfaces (docker, veth, lo) are
# skipped because they have no backing physical device.
IP=""
for IFACE in /sys/class/net/*; do
    NAME=$(basename "$IFACE")
    if [[ ! -e $IFACE/device || -d $IFACE/wireless || $(cat "$IFACE/type") != 1 ]]; then
        echo "Interface $NAME: skipped (not a wired physical interface)"
        continue
    fi
    IP=$(ip -4 -o addr show dev "$NAME" scope global | awk '{split($4, a, "/"); print a[1]; exit}')
    echo "Interface $NAME: operstate=$(cat "$IFACE/operstate") ip=${IP:-<none>}"
    [[ -n $IP ]] && break
done

echo "Detected IP: $IP"

echo "Monitors before:"
xrandr --query 2>&1 | grep -E ' (dis)?connected' | sed 's/^/  /'

# Runs the layout script, logging its output and exit status
run_layout() {
    echo "Running $1"
    "$1"
    echo "Layout script exited with status $?"
    echo "Monitors after:"
    xrandr --query 2>&1 | grep -E ' (dis)?connected' | sed 's/^/  /'
}

# Checks according to the network
if [[ $IP == 192.168.1.* ]]; then
    echo "Home network detected"
    run_layout /home/arliones/.screenlayout/home.sh

elif [[ $IP == 191.36.9.* ]]; then
    echo "Corporate network detected"
    run_layout /home/arliones/.screenlayout/ifsc.sh

# elif [[ $IP == 172.16.* || $IP == 172.17.* ]]; then
#     echo "Lab network detected"
#     run_layout /path/to/lab_script.sh

else
    echo "Unknown network. No matching script."
fi

echo "===== Run finished ====="
