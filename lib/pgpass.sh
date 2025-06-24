#!/bin/bash
# ~/.pgpass management functions

pgpass::file() {
    echo "$HOME/.pgpass"
}

pgpass::ensure() {
    local pgp
    pgp="$(pgpass::file)"
    [[ -f "$pgp" ]] || touch "$pgp"
    chmod 600 "$pgp"
}

pgpass::list() {
    local pgp
    pgp="$(pgpass::file)"
    mapfile -t lines < "$pgp"
    if (( ${#lines[@]} == 0 )); then
        echo "No entries found"
        return 0
    fi
    local i
    for i in "${!lines[@]}"; do
        printf "%2d) %s\n" "$i" "${lines[$i]}"
    done
}

pgpass::add() {
    pgpass::ensure
    local host port db user pass line
    read -r -p "Host: " host
    read -r -p "Port [5432]: " port
    port=${port:-5432}
    read -r -p "Database [*]: " db
    db=${db:-*}
    read -r -p "User: " user
    read -r -s -p "Password: " pass
    echo
    line="${host}:${port}:${db}:${user}:${pass}"
    local pgp
    pgp="$(pgpass::file)"
    if grep -Fqx "$line" "$pgp"; then
        echo "Entry already exists"
        return 1
    fi
    echo "$line" >> "$pgp"
    echo "Added"
}

pgpass::delete() {
    local idx pgp
    pgp="$(pgpass::file)"
    pgpass::list
    read -r -p "Index to delete: " idx
    sed -i "${idx}d" "$pgp"
    echo "Deleted"
}

pgpass::edit() {
    local idx pgp host port db user pass
    pgp="$(pgpass::file)"
    pgpass::list
    read -r -p "Index to edit: " idx
    IFS=: read -r host port db user pass < <(sed -n "${idx}p" "$pgp")
    read -r -p "Host [$host]: " tmp; host=${tmp:-$host}
    read -r -p "Port [$port]: " tmp; port=${tmp:-$port}
    read -r -p "Database [$db]: " tmp; db=${tmp:-$db}
    read -r -p "User [$user]: " tmp; user=${tmp:-$user}
    read -r -s -p "Password [hidden]: " tmp; echo; pass=${tmp:-$pass}
    sed -i "${idx}c ${host}:${port}:${db}:${user}:${pass}" "$pgp"
    echo "Updated"
}

pgpass::menu() {
    pgpass::ensure
    while true; do
        echo "--- .pgpass Menu ---"
        echo "1) List entries"
        echo "2) Add entry"
        echo "3) Edit entry"
        echo "4) Delete entry"
        echo "0) Back"
        read -r -p "Choose: " opt
        case "$opt" in
            1) pgpass::list ;;
            2) pgpass::add ;;
            3) pgpass::edit ;;
            4) pgpass::delete ;;
            0) break ;;
            *) echo "Invalid" ;;
        esac
    done
}
