#!/bin/bash
# Main launcher for PGTool
set -euo pipefail

PGTOOL_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PGTOOL_HOME

# --- Core libraries ---
# shellcheck source=lib/colors.sh
source "$PGTOOL_HOME/lib/colors.sh"
# shellcheck source=lib/log.sh
source "$PGTOOL_HOME/lib/log.sh"
# shellcheck source=lib/utils.sh
source "$PGTOOL_HOME/lib/utils.sh"
# shellcheck source=lib/menu.sh
source "$PGTOOL_HOME/lib/menu.sh"

plugins_menu_entries=()
plugins_callbacks=()

load_plugins() {
    local plugin
    for plugin in "$PGTOOL_HOME/plugins"/*.sh; do
        [[ -f "$plugin" ]] || continue
        # shellcheck source=/dev/null
        source "$plugin"
        if declare -f plugin_register >/dev/null; then
            local reg_output
            reg_output=$(plugin_register)
            eval "$reg_output"
            plugins_menu_entries+=("${PLUGIN[menu_entry]}")
            plugins_callbacks+=("${PLUGIN[callback]}")
            unset PLUGIN
            unset -f plugin_register
        fi
    done
}

show_menu() {
    menu::prompt "PGTool" plugins_menu_entries
}

main() {
    load_plugins
    log::init "$PGTOOL_HOME/pgtool.log"
    while true; do
        local opt
        opt=$(show_menu)
        if [[ "$opt" == "0" ]]; then
            break
        fi
        local cb="${plugins_callbacks[$((opt-1))]}"
        "$cb"
    done
}

main "$@"
