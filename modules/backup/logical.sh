#!/bin/bash
# Basic logical backup module

backup_logical::menu() {
  local host db user port
  read -r -p "Host: " host
  read -r -p "Port [5432]: " port
  port=${port:-5432}
  read -r -p "Database: " db
  read -r -p "User: " user
  backup_logical::run "$host" "$port" "$db" "$user"
}

backup_logical::run() {
  local host="$1" port="$2" db="$3" user="$4"
  if ! command -v pg_dump >/dev/null; then
    echo "pg_dump not found" >&2
    return 1
  fi
  local dir="$PGTOOL_HOME/backups"
  mkdir -p "$dir"
  local out
  out="$dir/${db}_$(date +%Y%m%d_%H%M%S).sql"
  PGPASSWORD="" pg_dump -h "$host" -p "$port" -U "$user" "$db" > "$out"
  echo "Backup saved to $out"
}
