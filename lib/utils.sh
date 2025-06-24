#!/bin/bash
# Generic helper functions

utils::read_num() {
    local prompt="$1" default="$2" re='^[0-9]+$' val
    while true; do
        read -r -p "$prompt" val
        val=${val:-$default}
        [[ "$val" =~ $re ]] && { echo "$val"; return 0; }
        echo "Invalid number" >&2
    done
}
