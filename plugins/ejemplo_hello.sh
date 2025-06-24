#!/bin/bash
## Plugin de demostración
plugin_register() {
  declare -A PLUGIN=(
    [name]="hello"
    [description]="Muestra un saludo de prueba"
    [menu_entry]="Saludar"
    [callback]="hello::run"
  )
  declare -p PLUGIN
}

hello::run() {
  echo "Hola desde un plugin!"
  return 0
}
