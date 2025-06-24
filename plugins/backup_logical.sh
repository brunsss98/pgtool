#!/bin/bash
## Plugin to run simple logical backups
plugin_register() {
  declare -A PLUGIN=(
    [name]="logical_backup"
    [description]="Run a simple pg_dump backup"
    [menu_entry]="Run Logical Backup"
    [callback]="backup_logical::menu"
  )
  declare -p PLUGIN
}

source "$PGTOOL_HOME/modules/backup/logical.sh"
