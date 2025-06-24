#!/bin/bash
# Main launcher for PGTool

PGTOOL_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PGTOOL_HOME

source "$PGTOOL_HOME/lib/colors.sh"
source "$PGTOOL_HOME/lib/log.sh"
source "$PGTOOL_HOME/lib/utils.sh"

plugins_menu_entries=()
plugins_callbacks=()

load_plugins() {
    local plugin
    for plugin in "$PGTOOL_HOME/plugins"/*.sh; do
        [[ -f "$plugin" ]] || continue
        source "$plugin"
        if declare -f plugin_register >/dev/null; then
            local reg_output
            reg_output=$(plugin_register)
            eval "$reg_output"
            plugins_menu_entries+=("${PLUGIN[menu_entry]}")
            plugins_callbacks+=("${PLUGIN[callback]}")
            unset PLUGIN
        fi
    done
}

show_menu() {
    echo -e "${MAGENTA}${BOLD}PGTool${NC}"
    local i=1
    for entry in "${plugins_menu_entries[@]}"; do
        echo -e "${CYAN}${BOLD}$i)${NC} ${WHITE}$entry${NC}"
        ((i++))
    done
    echo -e "${CYAN}${BOLD}0)${NC} ${WHITE}Exit${NC}"
}

main() {
    load_plugins
    log::init "$PGTOOL_HOME/pgtool.log"
    while true; do
        show_menu
        read -p "Select option: " opt
        if [[ "$opt" == "0" ]]; then
            break
        elif [[ "$opt" =~ ^[0-9]+$ && $opt -ge 1 && $opt -le ${#plugins_callbacks[@]} ]]; then
            local cb="${plugins_callbacks[$((opt-1))]}"
            "$cb"
        else
            echo "Invalid option"
        fi
    done
}

main "$@"
