#!/bin/bash
## Plugin to run legacy pgtool2.sh script
plugin_register() {
  declare -A PLUGIN=(
    [name]="legacy_backup"
    [description]="Run legacy pgtool2.sh backup menu"
    [menu_entry]="Legacy Backup Menu"
    [callback]="legacy_backup::run"
  )
  declare -p PLUGIN
}

legacy_backup::run() {
  bash "$PGTOOL_HOME/pgtool2.sh"
}
