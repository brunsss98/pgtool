#!/bin/bash
# Plugin to run backups from configuration
plugin_register() {
  declare -A PLUGIN=(
    [name]="backup_core"
    [description]="Run backups for all configured databases"
    [menu_entry]="Run Configured Backups"
    [callback]="backup_core::menu"
  )
  declare -p PLUGIN
}

source "$PGTOOL_HOME/modules/backup/core.sh"
