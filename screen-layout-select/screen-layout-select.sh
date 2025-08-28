#!/bin/bash

# Gets the IP of the connected interface
IP=$(hostname -I | awk '{print $1}')

echo "Detected IP: $IP"

# Checks according to the network
if [[ $IP == 192.168.1.* ]]; then
    echo "Home network detected"
    /home/arliones/.screenlayout/home.sh

elif [[ $IP == 191.36.9.* ]]; then
    echo "Corporate network detected"
    /home/arliones/.screenlayout/coord.sh

# elif [[ $IP == 172.16.* || $IP == 172.17.* ]]; then
#     echo "Lab network detected"
#     /path/to/lab_script.sh

else
    echo "Unknown network. No matching script."
fi
