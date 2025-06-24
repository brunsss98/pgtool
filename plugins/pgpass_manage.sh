#!/bin/bash
## Plugin for .pgpass management
plugin_register() {
  declare -A PLUGIN=(
    [name]="pgpass"
    [description]="Manage ~/.pgpass entries"
    [menu_entry]="Manage .pgpass"
    [callback]="pgpass::menu"
  )
  declare -p PLUGIN
}

source "$PGTOOL_HOME/lib/pgpass.sh"
