#!/bin/bash
# Simple menu rendering helpers

menu::prompt() {
  local title="$1" arr_name="$2" prompt="${3:-Select option: }"
  local -n arr="$arr_name"
  echo -e "${MAGENTA}${BOLD}${title}${NC}" >&2
  local i=1
  for entry in "${arr[@]}"; do
    echo -e "${CYAN}${BOLD}${i})${NC} ${WHITE}${entry}${NC}" >&2
    ((i++))
  done
  echo -e "${CYAN}${BOLD}0)${NC} ${WHITE}Exit${NC}" >&2
  local opt
  while true; do
    read -r -p "$prompt" opt
    if [[ "$opt" =~ ^[0-9]+$ && $opt -ge 0 && $opt -le ${#arr[@]} ]]; then
      echo "$opt"
      return 0
    fi
    echo "Invalid option" >&2
  done
}
