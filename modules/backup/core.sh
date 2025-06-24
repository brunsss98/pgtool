#!/bin/bash
# Core backup orchestration using pg_dump

# shellcheck source=../../lib/config.sh
source "$PGTOOL_HOME/lib/config.sh"

backup_core::run_all() {
    config::load
    local i
    for i in "${!HOSTS[@]}"; do
        backup_core::run_one "${HOSTS[i]}" "${PORTS[i]}" "${DBS[i]}" "${USERS[i]}"
    done
}

backup_core::run_one() {
    local host="$1" port="$2" db="$3" user="$4"
    [[ -z "$host" || -z "$db" || -z "$user" ]] && return
    mkdir -p "$PGTOOL_HOME/backups"
    local out="$PGTOOL_HOME/backups/${db}_$(date +%Y%m%d_%H%M%S).sql"
    pg_dump -h "$host" -p "$port" -U "$user" "$db" > "$out"
    echo "Saved $out"
}

backup_core::menu() {
    backup_core::run_all
    read -r -p "Press enter to continue" _
}
