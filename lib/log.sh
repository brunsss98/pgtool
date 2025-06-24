#!/bin/bash
# Basic logging utility

log_file=""

log::init() {
    local file="$1"
    log_file="$file"
    mkdir -p "$(dirname "$log_file")"
    touch "$log_file"
}

log::_write() {
    local level="$1" msg="$2"
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$ts][$level] $msg" >> "$log_file"
}

log::info() { log::_write INFO "$*"; }
log::warn() { log::_write WARN "$*"; }
log::error() { log::_write ERROR "$*"; }
