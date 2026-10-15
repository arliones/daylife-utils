#!/bin/bash

# Gets the IPv4 of the first connected wired interface. Wi-Fi is ignored since
# it doesn't imply a fixed location; virtual interfaces (docker, veth, lo) are
# skipped because they have no backing physical device.
IP=""
for IFACE in /sys/class/net/*; do
    [[ -e $IFACE/device && ! -d $IFACE/wireless && $(cat "$IFACE/type") == 1 ]] || continue
    IP=$(ip -4 -o addr show dev "$(basename "$IFACE")" scope global | awk '{split($4, a, "/"); print a[1]; exit}')
    [[ -n $IP ]] && break
done

echo "Detected IP: $IP"

# Checks according to the network
if [[ $IP == 192.168.1.* ]]; then
    echo "Home network detected"
    /home/arliones/.screenlayout/home.sh

elif [[ $IP == 191.36.9.* ]]; then
    echo "Corporate network detected"
    /home/arliones/.screenlayout/ifsc.sh

# elif [[ $IP == 172.16.* || $IP == 172.17.* ]]; then
#     echo "Lab network detected"
#     /path/to/lab_script.sh

else
    echo "Unknown network. No matching script."
fi
