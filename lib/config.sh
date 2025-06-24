#!/bin/bash
# Configuration loading utilities (no jq)

config::file() {
    echo "$PGTOOL_HOME/etc/connections.json"
}

# load configuration into arrays
config::load() {
    local conf
    conf="$(config::file)"
    HOSTS=()
    PORTS=()
    USERS=()
    DBS=()
    [[ -f "$conf" ]] || return 0
    local entry key value
    while IFS= read -r line; do
        line="${line#*[{]}"  # remove leading chars until {
        line="${line%*]}"    # remove trailing chars after ]
        [[ -z "$line" ]] && continue
        # split by "}," boundaries
        echo "$line" | tr -d '\n' | sed 's/},{/\n/g' | while IFS= read -r obj; do
            host=$(echo "$obj" | sed -n 's/.*"host"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
            port=$(echo "$obj" | sed -n 's/.*"port"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p')
            user=$(echo "$obj" | sed -n 's/.*"user"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
            db=$(echo "$obj" | sed -n 's/.*"database"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
            HOSTS+=("$host")
            PORTS+=("${port:-5432}")
            USERS+=("$user")
            DBS+=("$db")
        done
    done < "$conf"
}
