#!/bin/bash
# pg_backup_unificado_opt.sh - Backup PostgreSQL completo sin jq, optimizado

trap 'echo -e "\e[31m[ERROR]\e[0m Error en línea $LINENO. Abortando." >&2' ERR

# --- Colores y estilos ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[0;37m'
BOLD='\033[1m'
UNDERLINE='\033[4m'
NC='\033[0m'

CHECK="${GREEN}✔${NC}"
FAIL="${RED}✗${NC}"
ARROW="${CYAN}➜${NC}"
INFO="${CYAN}ℹ${NC}"
WARN="${YELLOW}⚠${NC}"

PG_DUMP_BIN=$(command -v pg_dump14 >/dev/null 2>&1 && echo pg_dump14 || echo pg_dump)

# --- Variables globales ---
declare -a EMPRESAS EMAILS BACKUPS_DIRS RETENTION_COUNT_ARR
declare -a HOSTS PORTS USERS DATABASES BACKUP_FREQS BACKUP_TYPES TIPOS ENTORNOS

GLOBAL_CONF="${HOME}/pg_backup/pg_backup_globals.conf"
if [[ -f "$GLOBAL_CONF" ]]; then
    source "$GLOBAL_CONF"
fi

# Ahora puedes definir rutas "derivadas" usando los valores que posiblemente ya han cambiado
DEFAULT_BACKUPS_DIR="${DEFAULT_BACKUPS_DIR:-${HOME}/pg_backup/backups}"
LOG_DIR="${LOG_DIR:-${DEFAULT_BACKUPS_DIR}/logs}"
CONFIG_DIR="${CONFIG_DIR:-${DEFAULT_BACKUPS_DIR}/config}"
CONFIG_FILE="${CONFIG_DIR}/pg_backup_config.json"
TIMEOUT="${TIMEOUT:-900}"

# --- Funciones globales ---

load_globals() {
    [[ -f "$GLOBAL_CONF" ]] && source "$GLOBAL_CONF"
}

save_globals() {
    mkdir -p "$(dirname "$GLOBAL_CONF")"
    cat > "$GLOBAL_CONF" <<EOF
DEFAULT_BACKUPS_DIR="$DEFAULT_BACKUPS_DIR"
LOG_DIR="$LOG_DIR"
CONFIG_DIR="$CONFIG_DIR"
TIMEOUT=$TIMEOUT
EOF
    echo -e "${GREEN}✔ Configuración global guardada en $GLOBAL_CONF${NC}"
}

ensure_pgpass_file() {
    local pgp="$HOME/.pgpass"
    [[ -f "$pgp" ]] || touch "$pgp"
    chmod 600 "$pgp"
}

sanitize() { echo "$1" | sed 's/[^a-zA-Z0-9_\-]/_/g'; }

detectar_entorno() {
    local v=$(echo "$1" | tr '[:upper:]' '[:lower:]')
    case "$v" in
        *prod*) echo "PROD" ;;
        *pre*)  echo "PRE"  ;;
        *des*|*dev*) echo "DES" ;;
        *test*) echo "TEST" ;;
        *qa*)   echo "QA"   ;;
        *int*)  echo "INT"  ;;
        *)      echo "DESCONOCIDO" ;;
    esac
}

log_msg() {
    local type="$1"; shift
    local color="${GREEN}"
    [[ $type == ERROR ]] && color="${RED}"
    [[ $type == WARN  ]] && color="${YELLOW}"
    [[ $type == INFO  ]] && color="${CYAN}"
    local file="${LOG_DIR}/backup.log"
    [[ $type == ERROR ]] && file="${LOG_DIR}/error.log"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${color}[$type]${NC} $*"
    echo "[$timestamp][$type] $*" >> "$file"
    logger -t pg_backup "[$type] $*"
}

echo_success(){ echo -e "${GREEN}✔ $*${NC}"; }
echo_error()  { echo -e "${RED}✗ $*${NC}"; }
echo_warn()   { echo -e "${YELLOW}⚠ $*${NC}"; }
echo_info()   { echo -e "${CYAN}ℹ $*${NC}"; }

validar_email() { [[ "$1" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; }

read_num() {
    local prompt="$1" default="$2" re='^[0-9]+$' val
    while true; do
        read -p "$prompt" val; val=${val:-$default}
        [[ "$val" =~ $re ]] && { echo "$val"; break; } || echo "Entrada inválida."
    done
}

leer_si_no() {
    local prompt="$1" default="$2" ans
    while true; do
        read -p "$prompt" ans; ans=${ans:-$default}
        case "${ans,,}" in s) echo true; break ;; n) echo false; break ;; *) echo "Responde s/n" ;; esac
    done
}

# --- Gestión .pgpass ---

pgpass_menu() {
    ensure_pgpass_file
    local pgp="$HOME/.pgpass"
    while true; do
        clear
        echo -e "${MAGENTA}${BOLD}╔══════════════════════════════════════╗${NC}"
        echo -e "${MAGENTA}${BOLD}║${WHITE}${BOLD}   GESTIÓN DE ARCHIVO  .pgpass    ${MAGENTA}${BOLD}║${NC}"
        echo -e "${MAGENTA}${BOLD}╠══════════════════════════════════════╣${NC}"
        echo -e "${CYAN}${BOLD}1)${NC} ${WHITE}Listar entradas${NC}"
        echo -e "${CYAN}${BOLD}2)${NC} ${WHITE}Añadir entrada${NC}"
        echo -e "${CYAN}${BOLD}3)${NC} ${WHITE}Editar entrada${NC}"
        echo -e "${CYAN}${BOLD}4)${NC} ${WHITE}Eliminar entrada${NC}"
        echo -e "${CYAN}${BOLD}0)${NC} ${WHITE}Volver${NC}"
        echo -ne "${CYAN}➜${NC} Seleccione opción: "
        read -r act
        case "$act" in
            1)  pgpass_list_entries ;      read -p "ENTER para continuar..." ;;
            2)  pgpass_add_entry   ;       read -p "ENTER para continuar..." ;;
            3)  pgpass_edit_entry  ;       read -p "ENTER para continuar..." ;;
            4)  pgpass_delete_entry;       read -p "ENTER para continuar..." ;;
            0)  break ;;
            *)  echo_warn "Opción inválida"; sleep 1 ;;
        esac
    done
}

pgpass_list_entries() {
    local pgp="$HOME/.pgpass"
    mapfile -t lines < "$pgp"
    if (( ${#lines[@]} == 0 )); then echo_warn "No hay entradas."; return; fi
    echo -e "${MAGENTA}${BOLD}\nEntradas actuales:${NC}"
    for i in "${!lines[@]}"; do printf "${CYAN}%2d)${NC} %s\n" "$i" "${lines[$i]}"; done
}

pgpass_add_entry() {
    local pgp="$HOME/.pgpass" host port db user pass line
    read -p "Host: " host
    read -p "Puerto [5432]: " port; port=${port:-5432}
    read -p "Base de datos [*]: " db; db=${db:-*}
    read -p "Usuario: " user
    read -s -p "Contraseña: " pass; echo
    line="${host}:${port}:${db}:${user}:${pass}"
    if grep -Fqx "$line" "$pgp"; then echo_warn "Entrada duplicada – ya existe."; return; fi
    echo "$line" >> "$pgp"
    chmod 600 "$pgp"
    echo_success "Entrada añadida."
}

pgpass_edit_entry() {
    local pgp="$HOME/.pgpass"; mapfile -t lines < "$pgp"
    (( ${#lines[@]} == 0 )) && { echo_warn "No hay entradas"; return; }
    pgpass_list_entries
    read -p "Índice a editar: " idx
    [[ ! "$idx" =~ ^[0-9]+$ || idx<0 || idx>=${#lines[@]} ]] && { echo_warn "Índice inválido"; return; }
    IFS=':' read -r host port db user pass <<< "${lines[$idx]}"
    echo "Deja vacío para mantener valor actual."
    read -p "Host [$host]: " n; host=${n:-$host}
    read -p "Puerto [$port]: " n; port=${n:-$port}
    read -p "Base de datos [$db]: " n; db=${n:-$db}
    read -p "Usuario [$user]: " n; user=${n:-$user}
    read -s -p "Contraseña [****]: " n; echo; pass=${n:-$pass}
    lines[$idx]="${host}:${port}:${db}:${user}:${pass}"
    printf "%s\n" "${lines[@]}" > "$pgp"
    chmod 600 "$pgp"
    echo_success "Entrada actualizada."
}

pgpass_delete_entry() {
    local pgp="$HOME/.pgpass"; mapfile -t lines < "$pgp"
    (( ${#lines[@]} == 0 )) && { echo_warn "No hay entradas"; return; }
    pgpass_list_entries
    read -p "Índice a eliminar: " idx
    [[ ! "$idx" =~ ^[0-9]+$ || idx<0 || idx>=${#lines[@]} ]] && { echo_warn "Índice inválido"; return; }
    read -p "¿Confirmar eliminación? [s/N]: " c; [[ ! "${c,,}" =~ ^s$ ]] && { echo_warn "Cancelado"; return; }
    unset 'lines[idx]'
    printf "%s\n" "${lines[@]}" > "$pgp"
    chmod 600 "$pgp"
    echo_success "Entrada eliminada."
}

rotate_logs() {
    mkdir -p "$LOG_DIR"
    for file in "$LOG_DIR"/*.log; do
        [[ -f $file && $(stat -c%s "$file") -gt 10485760 ]] && mv "$file" "$file.$(date +%s).old"
    done
}

check_disk_space() {
    local dir="$1" min_free_gb="${2:-2}" free_gb
    free_gb=$(df -BG "$dir" 2>/dev/null | awk 'NR==2{gsub("G","",$4);print $4}')
    [[ -z "$free_gb" || "$free_gb" -lt "$min_free_gb" ]] && { log_msg ERROR "Espacio insuficiente en $dir (${free_gb:-0}GB)"; return 1; }
    return 0
}

clear_config_arrays() {
    EMPRESAS=(); EMAILS=(); BACKUPS_DIRS=(); RETENTION_COUNT_ARR=()
    HOSTS=(); PORTS=(); USERS=(); DATABASES=(); BACKUP_FREQS=()
    BACKUP_TYPES=(); TIPOS=(); ENTORNOS=()
}

load_config() {
    clear_config_arrays
    if [[ ! -s "$CONFIG_FILE" ]]; then
        echo_warn "Archivo de configuración vacío o no existe: $CONFIG_FILE"
        return
    fi
    local inside=0 entry=""
    while IFS= read -r line; do
        line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [[ "$line" == "[" || "$line" == "]" ]] && continue
        if [[ "$line" == "{" ]]; then inside=1; entry=""; continue; fi
        if [[ "$line" =~ ^\}[,]*$ ]]; then
            inside=0
            entry=$(echo "$entry" | sed 's/,$//')
            local empresa email backups_dir retention_count host port user db freqs btype tipo entorno

            empresa=$(echo "$entry" | sed -n 's/.*"empresa"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
            email=$(echo "$entry" | sed -n 's/.*"email_alerta"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
            backups_dir=$(echo "$entry" | sed -n 's/.*"backups_dir"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
            retention_count=$(echo "$entry" | sed -n 's/.*"retention_count"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p')
            host=$(echo "$entry" | sed -n 's/.*"host"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
            port=$(echo "$entry" | sed -n 's/.*"port"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p')
            user=$(echo "$entry" | sed -n 's/.*"user"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
            db=$(echo "$entry" | sed -n 's/.*"database"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
            freqs=$(echo "$entry" | sed -n 's/.*"backup_frequency"[[:space:]]*:[[:space:]]*\[\(.*\)\].*/\1/p' | sed 's/[", ]//g' | tr ',' ';')
            btype=$(echo "$entry" | sed -n 's/.*"backup_type"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
            tipo=$(echo "$entry" | sed -n 's/.*"tipo"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
            entorno=$(echo "$entry" | sed -n 's/.*"entorno"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

            [[ -z "$empresa" ]] && empresa="EMPRESA_NO_DEFINIDA"
            [[ -z "$email" ]] && email=""
            [[ -z "$backups_dir" ]] && backups_dir="$DEFAULT_BACKUPS_DIR"
            [[ -z "$retention_count" ]] && retention_count=30
            [[ -z "$port" ]] && port=5432
            [[ -z "$btype" ]] && btype="full"
            [[ -z "$tipo" ]] && tipo="LOGICO"

            if [[ -n "$host" && -n "$user" && -n "$db" ]]; then
                EMPRESAS+=("$empresa")
                EMAILS+=("$email")
                BACKUPS_DIRS+=("$backups_dir")
                RETENTION_COUNT_ARR+=("$retention_count")
                HOSTS+=("$host")
                PORTS+=("$port")
                USERS+=("$user")
                DATABASES+=("$db")
                BACKUP_FREQS+=("$freqs")
                BACKUP_TYPES+=("$btype")
                TIPOS+=("${tipo^^}")
                ENTORNOS+=("$entorno")
            else
                echo_warn "Configuración omitida por falta de host/user/db en entrada: $entry"
            fi
            continue
        fi
        if [[ $inside -eq 1 ]]; then
            entry+="$line"$'\n'
        fi
    done < "$CONFIG_FILE"
    echo "Total configuraciones encontradas: ${#HOSTS[@]}"
}

save_config() {
    local tmpfile="${CONFIG_FILE}.tmp"
    {
        echo "["
        local count=${#HOSTS[@]}
        for ((i=0; i<count; i++)); do
            echo "  {"
            echo "    \"empresa\": \"${EMPRESAS[i]//\"/\\\"}\","
            echo "    \"email_alerta\": \"${EMAILS[i]//\"/\\\"}\","
            echo "    \"backups_dir\": \"${BACKUPS_DIRS[i]//\"/\\\"}\","
            echo "    \"retention_count\": ${RETENTION_COUNT_ARR[i]:-30},"
            echo "    \"host\": \"${HOSTS[i]//\"/\\\"}\","
            echo "    \"port\": ${PORTS[i]:-5432},"
            echo "    \"user\": \"${USERS[i]//\"/\\\"}\","
            echo "    \"database\": \"${DATABASES[i]//\"/\\\"}\","
            echo "    \"entorno\": \"${ENTORNOS[i]//\"/\\\"}\","
            echo -n "    \"backup_frequency\": ["
            IFS=';' read -ra freqs <<< "${BACKUP_FREQS[i]}"
            for j in "${!freqs[@]}"; do
                printf "\"%s\"" "${freqs[j]}"
                (( j < ${#freqs[@]} -1 )) && echo -n ", "
            done
            echo "],"
            echo "    \"backup_type\": \"${BACKUP_TYPES[i]//\"/\\\"}\","
            echo "    \"tipo\": \"${TIPOS[i]}\""
            if (( i == count -1 )); then
                echo "  }"
            else
                echo "  },"
            fi
        done
        echo "]"
    } > "$tmpfile"
    mv "$tmpfile" "$CONFIG_FILE"
    echo_success "Configuración guardada en $CONFIG_FILE"
}


print_table() {
    local -n hdr=$1
    local -n fmt=$2
    local -n rows_array=$3

    local w=1
    for f in "${fmt[@]}"; do
        if [[ $f =~ %-?([0-9]+)s ]]; then
            w=$((w + ${BASH_REMATCH[1]} + 3))
        fi
    done

    echo -e "${MAGENTA}${BOLD}╔$(printf '═%.0s' $(seq 1 $((w-2))))╗${NC}"
    printf "${MAGENTA}${BOLD}║${NC}"
    for ((i=0; i<${#hdr[@]}; i++)); do
        printf "${fmt[i]}" "${hdr[i]}"
        printf "${MAGENTA}${BOLD}║${NC}"
    done
    echo
    echo -e "${MAGENTA}${BOLD}╠$(printf '═%.0s' $(seq 1 $((w-2))))╣${NC}"

    for row in "${rows_array[@]}"; do
        IFS=$'\t' read -r -a cols <<< "$row"
        printf "${MAGENTA}${BOLD}║${NC}"
        for ((i=0; i<${#cols[@]}; i++)); do
            printf "${WHITE}$(printf "${fmt[i]}" "${cols[i]}")${NC}"
            printf "${MAGENTA}${BOLD}║${NC}"
        done
        echo
    done

    echo -e "${MAGENTA}${BOLD}╚$(printf '═%.0s' $(seq 1 $((w-2))))╝${NC}"
}

print_entries() {
    load_config

    echo -e "\n${MAGENTA}${BOLD}Configuraciones de Backup${NC}"

    local headers=( "Idx" "Host" "Puerto" "Usuario" "Base de Datos" "Entorno" "Frecuencia" "Tipo Backup" "Tipo" "Tiempo Rest." "Empresa" )
    local formats=( " %-3s " " %-20s " " %-6s " " %-8s " " %-14s " " %-7s " " %-20s " " %-12s " " %-6s " " %-12s " " %-10s " )

    local rows=()
    local total=${#HOSTS[@]}

    if (( total > 0 )); then
        for ((i=0; i<total; i++)); do
            local freq_display="${BACKUP_FREQS[i]}"
            [[ ${#freq_display} -gt 20 ]] && freq_display="${freq_display:0:17}..."

            local tiempo_restante
            tiempo_restante=$(tiempo_para_proximo_backup "${BACKUP_FREQS[i]}")

            rows+=( "$i	${HOSTS[i]}	${PORTS[i]}	${USERS[i]}	${DATABASES[i]}	${ENTORNOS[i]}	$freq_display	${BACKUP_TYPES[i]}	${TIPOS[i]}	$tiempo_restante	${EMPRESAS[i]}" )
        done
    fi

    print_table headers formats rows
}

eliminar_backups_manualmente() {
    load_config
    local backups_dir="${BACKUPS_DIRS[0]:-$DEFAULT_BACKUPS_DIR}"
    echo_info "Buscando backups disponibles en $backups_dir..."
    mapfile -t files < <(find "$backups_dir" -type f \( -name '*.dump.gz' -o -name '*.tar.gz' \) | sort -r)

    if (( ${#files[@]} == 0 )); then
        echo_warn "No se encontraron archivos de backup."
        return 1
    fi

    echo_info "Backups disponibles:"
    for i in "${!files[@]}"; do
        local size_hr
        size_hr=$(numfmt --to=iec --suffix=B "$(stat -c%s "${files[i]}")" 2>/dev/null || echo "N/A")
        echo "  $i) ${files[i]} (${size_hr})"
    done

    echo
    echo "Introduce los índices separados por espacio para eliminar, o 'cancelar' para salir:"
    read -ra indices
    if [[ "${indices[0],,}" == "cancelar" ]]; then
        echo_info "Operación cancelada."
        return 0
    fi

    for idx in "${indices[@]}"; do
        if [[ "$idx" =~ ^[0-9]+$ ]] && (( idx >= 0 && idx < ${#files[@]} )); then
            echo_info "Eliminando ${files[idx]}..."
            rm -v "${files[idx]}"
        else
            echo_warn "Índice inválido: $idx"
        fi
    done
}

run_backup_logico() {
    local i=$1
    local intentos=0
    local max_intentos=3
    while (( intentos < max_intentos )); do
        if _run_backup_logico_internal "$i"; then
            return 0
        else
            ((intentos++))
            log_msg WARN "Reintentando backup lógico ($intentos/$max_intentos)..."
            sleep 5
        fi
    done
    log_msg ERROR "Backup lógico fallido tras $max_intentos intentos"
    return 1
}

_run_backup_logico_internal() {
    local i=$1
    local entorno="${ENTORNOS[i]}"
    local host="${HOSTS[i]}"
    local port="${PORTS[i]}"
    local user="${USERS[i]}"
    local database="${DATABASES[i]}"
    local backups_dir="${BACKUPS_DIRS[i]}"
    local empresa="${EMPRESAS[i]}"
    local email="${EMAILS[i]}"

    export EMPRESA="$empresa"
    export EMAIL_ALERTA="$email"

    local safe_dbname safe_host safe_port fecha base_dir backup_dir custom_file ret
    safe_dbname=$(sanitize "$database")
    safe_host=$(sanitize "$host")
    safe_port=$(sanitize "$port")
    fecha=$(date +%Y%m%d_%H%M%S)

    # Guarda directo en el dir base, sin subdirectorios intermedios
    base_dir="${backups_dir}"
    backup_dir="${base_dir}/backup_${entorno}_${safe_host}_${safe_port}_${safe_dbname}_logico_${fecha}_dir"
    custom_file="${base_dir}/backup_${entorno}_${safe_host}_${safe_port}_${safe_dbname}_logico_${fecha}.dump"

    mkdir -p "$base_dir"
    if ! check_disk_space "$base_dir" 5; then
        return 1
    fi

    local error_log="${base_dir}/backup_${safe_dbname}_${fecha}.err"
    local out_log="${base_dir}/backup_${safe_dbname}_${fecha}.log"

    local pass_opt=""
    pass_opt=$(awk -F: -v h="$host" -v p="$port" -v u="$user" \
        '$1==h && $2==p && $4==u {print $5; exit}' ~/.pgpass 2>/dev/null)
    [[ -n "$pass_opt" ]] && export PGPASSWORD="$pass_opt"

    log_msg INFO "Backup lógico (directory, $JOBS jobs) inicio: $host:$port/$database en $entorno"

    local start_ts=$(date +%s)
    ret=1

    for attempt in 1 2 3; do
        rm -rf "$backup_dir"
        "$PG_DUMP_BIN" -h "$host" -p "$port" -U "$user" -d "$database" -F d -j "$JOBS" -f "$backup_dir" >"$out_log" 2>"$error_log"
        ret=$?
        if (( ret == 0 )); then
            break
        else
            log_msg ERROR "Backup lógico (directory) fallido intento $attempt para $host:$port/$database. Reintentando en 10s..."
            sleep 10
        fi
    done

    local used_fallback=0
    if (( ret != 0 )); then
        log_msg WARN "Intentando fallback a formato custom..."
        for attempt in 1 2; do
            rm -f "$custom_file"
            "$PG_DUMP_BIN" -h "$host" -p "$port" -U "$user" -d "$database" -F c -f "$custom_file" >"$out_log" 2>"$error_log"
            ret=$?
            if (( ret == 0 )); then
                used_fallback=1
                rm -rf "$backup_dir"
                break
            else
                log_msg ERROR "Fallback custom fallido intento $attempt. Reintentando en 10s..."
                sleep 10
            fi
        done
    fi

    local end_ts=$(date +%s)
    local elapsed=$((end_ts - start_ts))

    if (( ret != 0 )); then
        log_msg ERROR "Backup lógico fallido tras varios intentos (directory y custom): $host:$port/$database"
        send_error_email "$database" "$host" "Backup lógico fallido (dir+custom)"
        return 1
    fi

    local final_path
    if (( used_fallback == 1 )); then
        final_path="$custom_file"
        #sha256sum "$final_path" > "${final_path}.sha256"
    else
        final_path="$backup_dir"
        #find "$final_path" -type f -exec sha256sum {} \; > "$final_path/backup_checksums.sha256"
    fi

    local size_bytes size_hr
    size_bytes=$(du -sb "$final_path" | awk '{print $1}')
    size_hr=$(numfmt --to=iec --suffix=B "$size_bytes" 2>/dev/null || echo "${size_bytes}B")

    echo "$(date +%Y-%m-%d_%H:%M:%S),$host,$database,$([[ $used_fallback -eq 1 ]] && echo 'custom' || echo 'directory'),gzip:9,$elapsed,$size_bytes,PRIMARIO" \
        >> "${base_dir}/backup_metrics.csv"

    log_msg INFO "Backup lógico OK: $final_path (tiempo: ${elapsed}s, tamaño: ${size_hr})"
    send_success_email "$database" "$host" "$final_path"
    return 0
}

run_backup_fisico() {
    local i=$1
    local entorno="${ENTORNOS[i]}"
    local host="${HOSTS[i]}"
    local port="${PORTS[i]}"
    local user="${USERS[i]}"
    local backups_dir="${BACKUPS_DIRS[i]}"
    local db="${DATABASES[i]}"
    local empresa="${EMPRESAS[i]}"
    local email="${EMAILS[i]}"

    export EMPRESA="$empresa"
    export EMAIL_ALERTA="$email"

    local safe_host safe_port safe_db fecha backup_file tempdir
    safe_host=$(sanitize "$host")
    safe_port=$(sanitize "$port")
    safe_db=$(sanitize "$db")
    fecha=$(date +%Y%m%d_%H%M%S)

    mkdir -p "$backups_dir"
    if ! check_disk_space "$backups_dir" 5; then
        return 1
    fi

    backup_file="${backups_dir}/backup_${entorno}_${safe_host}_${safe_port}_${safe_db}_fisico_${fecha}.tar.gz"
    tempdir="${backups_dir}/temp_pg_basebackup_${fecha}"

    log_msg INFO "Backup físico: $host:$port/$db"

    local tblspc_base="${backups_dir}/tblspc_copy"
    mkdir -p "$tblspc_base"

    mapfile -t MAPPINGS < <(
        PGPASSWORD="${PGPASSWORD:-}" psql -h "$host" -p "$port" -U "$user" -d postgres -Atc "
            SELECT pg_tablespace_location(oid) || '|' || spcname
            FROM pg_tablespace
            WHERE spcname NOT IN ('pg_default','pg_global') AND pg_tablespace_location(oid) IS NOT NULL;
        "
    )

    local ts_args=()
    for mapping in "${MAPPINGS[@]}"; do
        local orig_path="${mapping%%|*}"
        local spcname="${mapping##*|}"
        local dest_path="${tblspc_base}/${spcname}"
        mkdir -p "$dest_path"
        ts_args+=( "--tablespace-mapping=${orig_path}=${dest_path}" )
    done

    if ! timeout "$TIMEOUT" pg_basebackup -h "$host" -p "$port" -U "$user" -D "$tempdir" -Ft -X fetch -P -v "${ts_args[@]}"; then
        log_msg ERROR "Backup físico fallo: $host:$port"
        send_notify fail "backup físico" "Backup físico fallido"
        rm -rf "$tempdir"
        return 1
    fi

    local tgz_file
    tgz_file=$(find "$tempdir" -name "*.tar" | head -n 1)
    if [[ -n "$tgz_file" ]]; then
        pigz -p "$JOBS" -6 "$tgz_file"  
        tgz_file="${tgz_file}.gz"
        mv "$tgz_file" "$backup_file"
        #sha256sum "$backup_file" > "${backup_file}.sha256"
        log_msg INFO "Backup físico OK: $backup_file"
        send_notify ok "backup físico" "$backup_file"
    else
        log_msg ERROR "No se encontró archivo .tar en $tempdir"
        send_notify fail "backup físico" "No se encontró archivo .tar generado"
        rm -rf "$tempdir"
        return 1
    fi
    rm -rf "$tempdir"
    return 0
}

limpiar_backups_antiguos() {
    load_config
    for i in "${!BACKUPS_DIRS[@]}"; do
        local keep="${RETENTION_COUNT_ARR[$i]:-30}"
        local dir="${BACKUPS_DIRS[$i]:-$DEFAULT_BACKUPS_DIR}"

        log_msg INFO "Manteniendo sólo las $keep copias más recientes en $dir (el resto se eliminará)"

        if [[ -d "$dir" ]]; then
            mapfile -t files < <(
                ls -1t "$dir"/*.dump.gz "$dir"/*.tar.gz "$dir"/*.sha256 2>/dev/null
            )
            if (( ${#files[@]} > keep )); then
                log_msg INFO "  → Total encontrados: ${#files[@]}; Eliminando $(( ${#files[@]} - keep )) archivos antiguos"
                printf '%s\n' "${files[@]:keep}" | xargs -r rm -f --
            else
                log_msg INFO "  → Sólo ${#files[@]} archivos; nada que hacer"
            fi
        else
            log_msg WARN "Directorio de backups no existe: $dir (saltando)"
        fi
    done
}


toca_backup() {
    local freq=$(echo "$1" | tr '[:upper:]' '[:lower:]')
    local hour_now=$((10#$(date +%H)))
    local min_now=$((10#$(date +%M)))
    local day_of_week=$((10#$(date +%u)))  # 1 = lunes ... 7 = domingo
    local day_of_month=$((10#$(date +%d)))
    local ventana=5

    declare -A dias_semana=(
      ["lunes"]=1 ["martes"]=2 ["miércoles"]=3 ["miercoles"]=3 ["jueves"]=4
      ["viernes"]=5 ["sábado"]=6 ["sabado"]=6 ["domingo"]=7
    )

    # 1. Diaria
    [[ "$freq" == "diaria" || "$freq" == "daily" ]] && return 0

    # 2. Semanal (nombre día)
    if [[ "${dias_semana[$freq]+_}" ]]; then
        [[ "${dias_semana[$freq]}" -eq "$day_of_week" ]] && return 0 || return 1
    fi

    # 3. Mensual (mensual:dia)
    if [[ "$freq" =~ ^mensual:([0-9]{1,2})$ ]]; then
        local dia_mes="${BASH_REMATCH[1]}"
        [[ "$day_of_month" -eq "$dia_mes" ]] && return 0 || return 1
    fi

    # 4. Mensual genérico (1 de mes)
    [[ "$freq" == "mensual" || "$freq" == "monthly" ]] && [[ "$day_of_month" -eq 1 ]] && return 0 || [[ "$freq" == "mensual" || "$freq" == "monthly" ]] && return 1

    # 5. Cada X días
    if [[ "$freq" =~ ^cada([0-9]+)dias$ ]]; then
        local n="${BASH_REMATCH[1]}"
        if (( n > 0 && (day_of_month - 1) % n == 0 )); then
            return 0
        else
            return 1
        fi
    fi

    # 6. Cada X horas
    if [[ "$freq" =~ ^cada([0-9]+)horas?$ ]]; then
        local h="${BASH_REMATCH[1]}"
        if (( h > 0 && hour_now % h == 0 && min_now <= ventana )); then
            return 0
        else
            return 1
        fi
    fi

    # 7. Cada X minutos
    if [[ "$freq" =~ ^cada([0-9]+)minutos?$ ]]; then
        local m="${BASH_REMATCH[1]}"
        if (( m > 0 && min_now % m == 0 )); then
            return 0
        else
            return 1
        fi
    fi

    # 8. Hora exacta tipo hora06
    if [[ "$freq" =~ ^hora([0-9]{2})$ ]]; then
        local h="${BASH_REMATCH[1]}"
        if (( hour_now == 10#$h && min_now <= ventana )); then
            return 0
        else
            return 1
        fi
    fi

    # 9. Ninguna/off
    [[ "$freq" == "ninguna" || "$freq" == "none" || "$freq" == "off" ]] && return 1

    # 10. Compatibilidad
    [[ "$freq" == "semanal" || "$freq" == "weekly" ]] && [[ "$day_of_week" -eq 3 ]] && return 0 || [[ "$freq" == "semanal" || "$freq" == "weekly" ]] && return 1

    # 11. DEFAULT: ejecuta (por compatibilidad con frecuencias raras)
    return 0
}

tiempo_para_proximo_backup() {
    local freqs_str="$1"
    local now_epoch=$(date +%s)
    local min_diff=99999999

    IFS=';' read -ra freqs <<< "$freqs_str"
    for freq in "${freqs[@]}"; do
        local diff_sec=99999999
        case "$freq" in
            diaria|daily)
                local next_midnight=$(date -d "tomorrow 00:00" +%s)
                diff_sec=$((next_midnight - now_epoch))
                ;;
            semanal|weekly)
                local day_of_week=$((10#$(date +%u)))
                local days_to_sunday=$((7 - day_of_week))
                local next_sunday_midnight=$(date -d "$days_to_sunday days 00:00" +%s)
                diff_sec=$((next_sunday_midnight - now_epoch))
                ;;
            mensual|monthly)
                local next_month_first=$(date -d "$(date +%Y-%m-01) +1 month" +%s)
                diff_sec=$((next_month_first - now_epoch))
                ;;
            hora00|hora06|hora12|hora18)
                local target_hour=${freq//hora/}
                target_hour=$((10#$target_hour))
                local target_epoch=$(date -d "today $target_hour:00" +%s)
                if (( target_epoch <= now_epoch )); then
                    target_epoch=$(date -d "tomorrow $target_hour:00" +%s)
                fi
                diff_sec=$((target_epoch - now_epoch))
                ;;
            cada*horas)
                local horas=${freq//[^0-9]/}
                if [[ -z "$horas" || "$horas" -eq 0 ]]; then
                    diff_sec=99999999
                else
                    local hour_now=$((10#$(date +%H)))
                    local next_hour=$((( (hour_now / horas) + 1) * horas))
                    local next_time
                    if (( next_hour >= 24 )); then
                        next_hour=0
                        next_time=$(date -d "tomorrow $next_hour:00" +%s)
                    else
                        next_time=$(date -d "today $next_hour:00" +%s)
                    fi
                    diff_sec=$((next_time - now_epoch))
                fi
                ;;
            ninguna|none|off)
                diff_sec=99999999
                ;;
            *)
                diff_sec=0
                ;;
        esac
        (( diff_sec < min_diff )) && min_diff=$diff_sec
    done

    if (( min_diff < 0 )); then
        echo "0h0m"
        return
    fi
    local hours=$((min_diff / 3600))
    local minutes=$(((min_diff % 3600) / 60))
    echo "${hours}h${minutes}m"
}

send_email() {
    local subject="$1" body="$2" to=$(echo "${EMAIL_ALERTA:-}" | tr -d ' ')
    if [[ -z "$to" ]]; then
        echo_warn "Email no configurado."
        return
    fi
    if command -v mail >/dev/null; then
        echo "$body" | mail -s "$subject" "$to"
    else
        echo_warn "'mail' no encontrado, no se puede enviar correo."
    fi
}

send_notify() {
    if [[ "$1" == "ok" ]]; then
        send_email "[BACKUP-OK][${EMPRESA:-EMPRESA}] $2" "$3"
    else
        send_email "[BACKUP-ERROR][${EMPRESA:-EMPRESA}] $2" "$3"
    fi
}

send_success_email() {
    send_notify ok "$1 backup exitoso" "$2"
}

send_error_email() {
    send_notify fail "$1 backup fallido" "$2"
}

test_connection() {
    timeout 10 psql -h "$1" -p "$2" -U "$3" -d "$4" -c "SELECT 1;" &>/dev/null
}

get_parallel_jobs() {
    local total
    total=$(nproc)
    local jobs=$(( total / 2 ))
    (( jobs < 1 )) && jobs=1
    echo "$jobs"
}

JOBS=$(get_parallel_jobs)


run_all_backups_force() {
    rotate_logs
    load_config
    limpiar_backups_antiguos

    if (( ${#HOSTS[@]} == 0 )); then
        echo_warn "No hay configuraciones para backup."
        return 1
    fi

    local count=0 success=0

    for i in "${!HOSTS[@]}"; do
        local entorno="${ENTORNOS[i]}"
        [[ -z "$entorno" ]] && entorno=$(detectar_entorno "${HOSTS[i]}")
        ENTORNOS[i]="$entorno"

        ((count++))

        if ! test_connection "${HOSTS[i]}" "${PORTS[i]}" "${USERS[i]}" "${DATABASES[i]}"; then
            log_msg ERROR "Fallo conexión: ${HOSTS[i]}:${PORTS[i]}/${DATABASES[i]}"
            continue
        fi

        if [[ "${TIPOS[i]}" == "FISICO" ]]; then
            if run_backup_fisico "$i"; then
                ((success++))
            fi
        else
            if run_backup_logico "$i"; then
                ((success++))
            fi
        fi
    done

    log_msg INFO "Backups forzados finalizados. Procesados: $count, Exitosos: $success"
}

run_all_backups() {
    rotate_logs
    load_config
    limpiar_backups_antiguos

    if (( ${#HOSTS[@]} == 0 )); then
        echo_warn "No hay configuraciones para backup."
        return 1
    fi

    local count=0 success=0

    for i in "${!HOSTS[@]}"; do
        local entorno="${ENTORNOS[i]}"
        [[ -z "$entorno" ]] && entorno=$(detectar_entorno "${HOSTS[i]}")
        ENTORNOS[i]="$entorno"

        ((count++))

        if ! test_connection "${HOSTS[i]}" "${PORTS[i]}" "${USERS[i]}" "${DATABASES[i]}"; then
            log_msg ERROR "Fallo conexión: ${HOSTS[i]}:${PORTS[i]}/${DATABASES[i]}"
            continue
        fi

        IFS=';' read -ra freqs_arr <<< "${BACKUP_FREQS[i]}"
        local ejecutar=1
        for freq in "${freqs_arr[@]}"; do
            if toca_backup "$freq"; then
                ejecutar=0
                break
            fi
        done
        if (( ejecutar )); then
            log_msg INFO "Saltando ${DATABASES[i]} — no toca backup (${BACKUP_FREQS[i]})"
            continue
        fi

        case "${TIPOS[i]}" in
            LOGICO)  if run_backup_logico "$i"; then ((success++)); fi ;;
            FISICO)  if run_backup_fisico "$i"; then ((success++)); fi ;;
            *)
                log_msg WARN "Tipo de backup desconocido '${TIPOS[i]}' para ${HOSTS[i]}:${PORTS[i]}/${DATABASES[i]}"
                ;;
        esac
    done

    log_msg INFO "Backups finalizados. Procesados: $count, Exitosos: $success"
}

show_backup_summary() {
    load_config
    echo -e "${BOLD}${UNDERLINE}Resumen backups recientes por base de datos:${NC}"
    local backups_dir="${BACKUPS_DIRS[0]:-$DEFAULT_BACKUPS_DIR}"

    mapfile -t recent_backups < <(
        find "$backups_dir" -type f \( -name '*.dump.gz' -o -name '*.tar.gz' \) -mtime -7 -printf '%TY-%Tm-%Td %TH:%TM %p\n' | sort -r
    )

    if (( ${#recent_backups[@]} == 0 )); then
        echo_warn "No se encontraron backups recientes en $backups_dir"
        return 1
    fi

    declare -a rows=()

    for line in "${recent_backups[@]}"; do
        local fecha path bd entorno size size_hr log_file
        fecha=$(echo "$line" | awk '{print $1, $2}')
        path=$(echo "$line" | awk '{print $3}')
        bd=$(basename "$path" | cut -d_ -f1)
        entorno=$(echo "$path" | awk -F/ '{print $(NF-2)}')
        size=$(stat -c%s "$path")
        size_hr=$(numfmt --to=iec --suffix=B "$size" 2>/dev/null || echo "${size}B")
        log_file="/var/lib/pgsql/pg_backup/logs/backup_$(date -d "$fecha" +%Y%m%d 2>/dev/null).log"
        [[ ! -f "$log_file" ]] && log_file="(no log)"

        rows+=( "$fecha"$'\t'"$entorno"$'\t'"$bd"$'\t'"$size_hr"$'\t'"$(basename "$path")"$'\t'"$(basename "$log_file")" )
    done

    local headers=( "Fecha" "Entorno" "Base de Datos" "Tamaño" "Backup" "Log Asociado" )
    local formats=( " %-16s " " %-8s " " %-14s " " %-8s " " %-40s " " %-20s " )

    print_table headers formats rows
}

export_single_bd_ad_hoc() {
    if [[ ! -f "$HOME/.pgpass" ]]; then
        echo_error "No se encontró archivo ~/.pgpass"
        echo "Crea ~/.pgpass con host:port:database:user:password"
        return 1
    fi

    mapfile -t hosts_array < <(
        grep -v '^#' "$HOME/.pgpass" 2>/dev/null |
        awk -F: '{print $1":"$2":"$4}' |
        sort -u
    )
    if (( ${#hosts_array[@]} == 0 )); then
        echo_error "No hay hosts disponibles en ~/.pgpass"
        return 1
    fi

    echo_info "Hosts disponibles:"
    for i in "${!hosts_array[@]}"; do
        echo "  $i) ${hosts_array[i]}"
    done

    local idx
    while true; do
        read -p "Selecciona host por índice: " idx
        if [[ "$idx" =~ ^[0-9]+$ ]] && (( idx >= 0 && idx < ${#hosts_array[@]} )); then
            break
        fi
        echo_warn "Índice inválido, inténtalo de nuevo."
    done

    IFS=':' read -r host port user <<< "${hosts_array[$idx]}"

    if ! test_connection "$host" "$port" "$user" "postgres"; then
        echo_error "No se pudo conectar a $host:$port como $user"
        read -p "¿Continuar de todos modos? [s/N]: " c
        [[ ! "$c" =~ ^[sS]$ ]] && return 1
    fi

    echo_info "Obteniendo bases de datos..."
    mapfile -t dbs < <(
        psql -h "$host" -p "$port" -U "$user" -d postgres -Atc \
            "SELECT datname FROM pg_database WHERE datistemplate = false;"
    )
    if (( ${#dbs[@]} == 0 )); then
        echo_warn "No se encontraron bases de datos"
        return 1
    fi

    echo_info "Bases disponibles:"
    for i in "${!dbs[@]}"; do
        echo "  $i) ${dbs[i]}"
    done

    local db_idx
    while true; do
        read -p "Selecciona base de datos por índice: " db_idx
        if [[ "$db_idx" =~ ^[0-9]+$ ]] && (( db_idx >= 0 && db_idx < ${#dbs[@]} )); then
            break
        fi
        echo_warn "Índice inválido, inténtalo de nuevo."
    done

    local db="${dbs[$db_idx]}"
    local fecha=$(date +%Y%m%d_%H%M%S)
    local safe_db=$(echo "$db" | sed 's/[^a-zA-Z0-9]/_/g')
    local safe_hostport=$(echo "${host}_${port}" | sed 's/[^a-zA-Z0-9]/_/g')
    local default_dir="${HOME}/pg_backup/backups/ad_hoc/${safe_hostport}"
    read -p "Ruta destino del backup [${default_dir}]: " backups_dir
    backups_dir=${backups_dir:-$default_dir}
    local backup_dir="${backups_dir}/${safe_db}_${fecha}_dir"
    mkdir -p "$backup_dir"

    echo_info "Ejecutando backup lógico DIRECTORY de $host:$port/$db (paralelo, "$JOBS" jobs, gzip:6) ... (en segundo plano)"
    (
        pg_dump -h "$host" -p "$port" -U "$user" -d "$db" -Fd -j "$JOBS" -Z 6 -f "$backup_dir" \
        && echo -e "\n${GREEN}✔ Backup de $db exportado a $backup_dir${NC}" \
        || echo -e "\n${RED}✗ Error exportando backup de $db${NC}"
    ) &

    local pid=$!
    echo_success "Backup lanzado en segundo plano (PID: $pid)"
    echo_info "Puedes revisar el directorio $backup_dir cuando termine el proceso."
}

restore_single_bd_ad_hoc() {
    if [[ ! -f "$HOME/.pgpass" ]]; then
        echo_error "No se encontró archivo ~/.pgpass"
        echo "Crea ~/.pgpass con host:port:database:user:password"
        return 1
    fi

    mapfile -t hosts_array < <(grep -v '^#' "$HOME/.pgpass" 2>/dev/null | awk -F: '{print $1":"$2":"$4}' | sort -u)
    if (( ${#hosts_array[@]} == 0 )); then
        echo_error "No hay hosts disponibles en ~/.pgpass"
        return 1
    fi

    echo_info "Hosts disponibles:"
    for i in "${!hosts_array[@]}"; do
        echo "  $i) ${hosts_array[i]}"
    done

    local idx
    while true; do
        read -p "Selecciona host por índice: " idx
        if [[ "$idx" =~ ^[0-9]+$ ]] && (( idx >= 0 && idx < ${#hosts_array[@]} )); then
            break
        else
            echo_warn "Índice inválido, intenta de nuevo."
        fi
    done

    IFS=':' read -r host port user <<< "${hosts_array[$idx]}"

    local default_dir="${HOME}/pg_backup/backups/ad_hoc/${host}_${port}"
    read -p "Ruta donde buscar backups [${default_dir}]: " ad_hoc_dir
    ad_hoc_dir=${ad_hoc_dir:-$default_dir}

    if [[ ! -d "$ad_hoc_dir" ]]; then
        echo_warn "No hay backups en $ad_hoc_dir"
        return 1
    fi

    mapfile -t files < <(find "$ad_hoc_dir" -type f -name '*.dump.gz' | sort -r)
    if (( ${#files[@]} == 0 )); then
        echo_warn "No se encontraron backups en $ad_hoc_dir"
        return 1
    fi

    echo_info "Backups disponibles:"
    for i in "${!files[@]}"; do
        echo "  $i) ${files[i]}"
    done

    while true; do
        read -p "Selecciona backup por índice: " file_idx
        if [[ "$file_idx" =~ ^[0-9]+$ ]] && (( file_idx >= 0 && file_idx < ${#files[@]} )); then
            break
        else
            echo_warn "Índice inválido, intenta de nuevo."
        fi
    done

    local backup_file="${files[$file_idx]}"

    read -p "Base de datos destino para restaurar: " restore_db
    read -p "Usuario destino [$user]: " restore_user
    restore_user=${restore_user:-$user}

    read -p "¿Proceder a restaurar $backup_file en $host:$port/$restore_db como $restore_user? [s/N]: " confirm
    [[ ! "$confirm" =~ ^[sS]$ ]] && echo_warn "Cancelado." && return 1

    log_msg INFO "Restaurando $backup_file en $host:$port/$restore_db"
    gunzip -c "$backup_file" | pg_restore -h "$host" -p "$port" -U "$restore_user" -d "$restore_db" -v
    if [[ $? -eq 0 ]]; then
        log_msg INFO "Restauración completada exitosamente"
    else
        log_msg ERROR "Error en restauración de $backup_file"
    fi
}

restore_backup() {
    load_config
    local backups_dir="${BACKUPS_DIRS[0]:-$DEFAULT_BACKUPS_DIR}"
    echo_info "Buscando backups disponibles en $backups_dir..."
    mapfile -t files < <(find "$backups_dir" -type f -name '*.dump.gz' | sort -r)

    if (( ${#files[@]} == 0 )); then
        echo_warn "No se encontraron archivos de backup."
        return 1
    fi

    local headers=( "Índice" "Archivo de Backup" )
    local formats=( " %-6s " " %-80s " )
    local rows=()
    for i in "${!files[@]}"; do
        rows+=( "$i	${files[i]}" )
    done

    print_table headers formats rows

    read -p "Introduce índice del backup a restaurar o 'cancelar' para salir: " choice
    [[ "$choice" == "cancelar" ]] && return 1

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 0 || choice >= ${#files[@]} )); then
        echo_error "Índice inválido."
        return 1
    fi

    local backup_file="${files[choice]}"

    read -p "Base de datos destino para restaurar: " restore_db
    read -p "Host destino [localhost]: " restore_host
    restore_host=${restore_host:-localhost}
    restore_port=$(read_num "Puerto destino [5432]: " 5432)
    read -p "Usuario destino [postgres]: " restore_user
    restore_user=${restore_user:-postgres}

    read -p "¿Proceder a restaurar $backup_file en $restore_host:$restore_port/$restore_db como $restore_user? [s/N]: " confirm
    [[ ! "$confirm" =~ ^[sS]$ ]] && echo_warn "Cancelado." && return 1

    log_msg INFO "Restaurando $backup_file en $restore_host:$restore_port/$restore_db"
    gunzip -c "$backup_file" | pg_restore -h "$restore_host" -p "$restore_port" -U "$restore_user" -d "$restore_db" -v
    if [[ $? -eq 0 ]]; then
        log_msg INFO "Restauración completada exitosamente"
    else
        log_msg ERROR "Error en restauración de $backup_file"
    fi
}

add_entry() {
    load_config
    echo -e "${MAGENTA}${BOLD}Añadir nueva configuración de backup${NC}"

    if [[ ! -f "$HOME/.pgpass" ]]; then
        echo_error "No se encontró archivo ~/.pgpass"
        echo "Crea ~/.pgpass con host:port:database:user:password"
        return 1
    fi

    mapfile -t hosts_array < <(grep -v '^#' "$HOME/.pgpass" 2>/dev/null | awk -F: '{print $1":"$2":"$4}' | sort -u)
    if (( ${#hosts_array[@]} == 0 )); then
        echo_error "No hay hosts disponibles en ~/.pgpass"
        return 1
    fi

    echo_info "Hosts disponibles:"
    for i in "${!hosts_array[@]}"; do
        echo "  $i) ${hosts_array[i]}"
    done
    local idx
    while true; do
        read -p "Selecciona host por índice: " idx
        if [[ "$idx" =~ ^[0-9]+$ ]] && (( idx >= 0 && idx < ${#hosts_array[@]} )); then
            break
        else
            echo_warn "Índice inválido, intenta de nuevo."
        fi
    done

    IFS=':' read -r host port user <<< "${hosts_array[$idx]}"

    if ! test_connection "$host" "$port" "$user" "postgres"; then
        echo_error "No se pudo conectar a $host:$port como $user"
        read -p "Continuar de todos modos? [s/N]: " c
        [[ ! "$c" =~ ^[sS]$ ]] && return 1
    fi

    echo_info "Obteniendo bases de datos..."
    mapfile -t dbs < <(psql -h "$host" -p "$port" -U "$user" -d postgres -Atc "SELECT datname FROM pg_database WHERE datistemplate = false;")
    if (( ${#dbs[@]} == 0 )); then
        echo_warn "No se encontraron bases de datos"
        return 1
    fi

    echo_info "Bases disponibles:"
    for i in "${!dbs[@]}"; do
        echo "  $i) ${dbs[i]}"
    done
    read -p "Selecciona bases (índices separados por espacio): " -a db_idx_arr
    selected_dbs=()
    for idx_db in "${db_idx_arr[@]}"; do
        if [[ "$idx_db" =~ ^[0-9]+$ ]] && (( idx_db >= 0 && idx_db < ${#dbs[@]} )); then
            selected_dbs+=("${dbs[$idx_db]}")
        fi
    done
    if (( ${#selected_dbs[@]} == 0 )); then
        echo_warn "No seleccionaste bases válidas"
        return 1
    fi

    read -p "Empresa [EMPRESA_NO_DEFINIDA]: " empresa
    empresa=${empresa:-EMPRESA_NO_DEFINIDA}

    read -p "Email alerta: " email_alerta
    if [[ -n "$email_alerta" ]]; then
        if ! validar_email "$email_alerta"; then
            echo_warn "Email inválido, se dejará vacío."
            email_alerta=""
        fi
    fi

    read -p "Ruta base backups [$DEFAULT_BACKUPS_DIR]: " backups_dir
    backups_dir=${backups_dir:-$DEFAULT_BACKUPS_DIR}

    retention_count=$(read_num "¿Cuántos backups mantener por configuración? [30]: " 30)

    read -p "Entorno [PROD/PRE/DES/TEST/QA/INT]: " entorno
    entorno=${entorno:-$(detectar_entorno "$host")}

    # Menú frecuencias ultra completo
    echo_info "Frecuencias disponibles:"
    echo " 1) diaria (todos los días a medianoche)"
    echo " 2) semanal (elige el día o días)"
    echo " 3) mensual (elige uno o varios días del mes)"
    echo " 4) cada X días"
    echo " 5) cada X horas"
    echo " 6) cada X minutos"
    echo " 7) horas exactas (ej: 00 06 14 23, puedes poner varias)"
    echo " 8) ninguna"
    read -p "Selecciona frecuencia (índice): " freq_idx

    freqs=()
    case "$freq_idx" in
        1) freqs=("diaria") ;;
        2)
            echo "Días de la semana: 1)Lunes 2)Martes 3)Miércoles 4)Jueves 5)Viernes 6)Sábado 7)Domingo"
            read -p "¿Qué día(s) de la semana? (números, puedes poner varios separados por espacio): " -a dias_semana
            for d in "${dias_semana[@]}"; do
                case "$d" in
                    1) freqs+=("lunes") ;;
                    2) freqs+=("martes") ;;
                    3) freqs+=("miercoles") ;;
                    4) freqs+=("jueves") ;;
                    5) freqs+=("viernes") ;;
                    6) freqs+=("sabado") ;;
                    7) freqs+=("domingo") ;;
                esac
            done
            ;;
        3)
            read -p "¿Qué día(s) del mes? (ej: 1 para el 1er día, 15 para el 15, puedes poner varios): " -a dias_mes
            for d in "${dias_mes[@]}"; do
                freqs+=("mensual:$d")
            done
            ;;
        4)
            read -p "¿Cada cuántos días?: " cada_cuanto
            freqs+=("cada${cada_cuanto}dias")
            ;;
        5)
            read -p "¿Cada cuántas horas?: " cada_horas
            freqs+=("cada${cada_horas}horas")
            ;;
        6)
            read -p "¿Cada cuántos minutos?: " cada_min
            freqs+=("cada${cada_min}minutos")
            ;;
        7)
            read -p "Introduce las horas exactas (formato 00 06 14 23, separados por espacio): " -a horas_especificas
            for h in "${horas_especificas[@]}"; do
                freqs+=("hora${h}")
            done
            ;;
        8) freqs=("ninguna") ;;
        *) freqs=("diaria") ;;
    esac

    backup_freq=$(IFS=';'; echo "${freqs[*]}")

    read -p "Tipo backup [full/schema/data]: " backup_type
    backup_type=${backup_type:-full}

    read -p "Tipo de backup [LOGICO/FISICO]: " tipo
    tipo=${tipo^^}
    [[ "$tipo" != "FISICO" ]] && tipo="LOGICO"

    for db in "${selected_dbs[@]}"; do
        EMPRESAS+=("$empresa")
        EMAILS+=("$email_alerta")
        BACKUPS_DIRS+=("$backups_dir")
        RETENTION_COUNT_ARR+=("$retention_count")
        HOSTS+=("$host")
        PORTS+=("$port")
        USERS+=("$user")
        DATABASES+=("$db")
        BACKUP_FREQS+=("$backup_freq")
        BACKUP_TYPES+=("$backup_type")
        TIPOS+=("$tipo")
        ENTORNOS+=("$entorno")
    done

    save_config
    echo_success "Configuración añadida"
}

edit_entry() {
    load_config
    if (( ${#HOSTS[@]} == 0 )); then
        echo_warn "No hay configuraciones para editar."
        return 1
    fi
    print_entries
    local idx
    while true; do
        read -p "Índice a editar: " idx
        if [[ "$idx" =~ ^[0-9]+$ ]] && (( idx >= 0 && idx < ${#HOSTS[@]} )); then
            break
        else
            echo_warn "Índice inválido, intenta de nuevo."
        fi
    done
    echo "Deja vacío para mantener valor actual."

    read -p "Host [${HOSTS[idx]}]: " new
    [[ -n "$new" ]] && HOSTS[idx]="$new"

    read -p "Puerto [${PORTS[idx]}]: " new
    [[ -n "$new" ]] && PORTS[idx]="$new"

    read -p "Usuario [${USERS[idx]}]: " new
    [[ -n "$new" ]] && USERS[idx]="$new"

    read -p "Base [${DATABASES[idx]}]: " new
    [[ -n "$new" ]] && DATABASES[idx]="$new"

    read -p "Entorno [${ENTORNOS[idx]}]: " new
    [[ -n "$new" ]] && ENTORNOS[idx]="$new"

    read -p "Frecuencia [${BACKUP_FREQS[idx]}]: " new
    [[ -n "$new" ]] && BACKUP_FREQS[idx]="$new"

    read -p "Tipo backup [${BACKUP_TYPES[idx]}]: " new
    [[ -n "$new" ]] && BACKUP_TYPES[idx]="$new"

    read -p "Tipo de backup [${TIPOS[idx]}]: " new
    new=${new^^}
    [[ -n "$new" ]] && TIPOS[idx]="$new"

    read -p "Empresa [${EMPRESAS[idx]}]: " new
    [[ -n "$new" ]] && EMPRESAS[idx]="$new"

    read -p "Email alerta [${EMAILS[idx]}]: " new
    [[ -n "$new" ]] && EMAILS[idx]="$new"

    read -p "Ruta backups [${BACKUPS_DIRS[idx]}]: " new
    [[ -n "$new" ]] && BACKUPS_DIRS[idx]="$new"

    retention_count=$(read_num "¿Cuántos backups mantener por configuración? [${RETENTION_COUNT_ARR[idx]}]: " "${RETENTION_COUNT_ARR[idx]}")
    RETENTION_COUNT_ARR[idx]="$retention_count"

    save_config
    echo_success "Configuración actualizada"
}

delete_entry() {
    load_config
    if (( ${#HOSTS[@]} == 0 )); then
        echo_warn "No hay configuraciones para eliminar."
        return 1
    fi
    print_entries
    local idx
    while true; do
        read -p "Índice a eliminar: " idx
        if [[ "$idx" =~ ^[0-9]+$ ]] && (( idx >= 0 && idx < ${#HOSTS[@]} )); then
            break
        else
            echo_warn "Índice inválido, intenta de nuevo."
        fi
    done
    read -p "¿Eliminar configuración para ${HOSTS[idx]}:${PORTS[idx]}/${DATABASES[idx]}? [s/N]: " c
    [[ ! "$c" =~ ^[sS]$ ]] && echo_warn "Cancelado." && return 1
    for arr in EMPRESAS EMAILS BACKUPS_DIRS RETENTION_COUNT_ARR HOSTS PORTS USERS DATABASES BACKUP_FREQS BACKUP_TYPES TIPOS ENTORNOS; do
        eval "$arr=(\"\${$arr[@]:0:$idx}\" \"\${$arr[@]:$((idx+1))}\")"
    done
    save_config
    echo_success "Configuración eliminada"
}


main_menu_unificado() {
    clear
    echo -e "${MAGENTA}${BOLD}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}${BOLD}║${WHITE}${BOLD}                   PANEL UNIFICADO BACKUP POSTGRESQL                         ${MAGENTA}${BOLD}║${NC}"
    echo -e "${MAGENTA}${BOLD}╠══════════════════════════════════════════════════════════════════════════════╣${NC}"

    # Sección: Operaciones de Backup
    echo -e "${CYAN}${BOLD} OPERACIONES DE BACKUP ${NC}"
    echo -e "${CYAN}${BOLD} 1)${NC} ${WHITE}Forzar ejecución de todos los backups${NC}"
    echo -e "${CYAN}${BOLD} 2)${NC} ${WHITE}Ejecutar backups según calendario${NC}"

    # Sección: Gestión de Configuración de Backups
    echo -e "${MAGENTA}──────────────────────────────────────────────────────────────────────────────${NC}"
    echo -e "${YELLOW}${BOLD} GESTIÓN DE CONFIGURACIONES DE BACKUP ${NC}"
    echo -e "${CYAN}${BOLD} 3)${NC}  ${WHITE}Añadir nueva configuración de backup${NC}"
    echo -e "${CYAN}${BOLD} 4)${NC}  ${WHITE}Editar configuración de backup${NC}"
    echo -e "${CYAN}${BOLD} 5)${NC}  ${WHITE}Eliminar configuración de backup${NC}"
    echo -e "${CYAN}${BOLD} 6)${NC}  ${WHITE}Listar configuraciones actuales${NC}"

    # Sección: Herramientas y Gestión de .pgpass
    echo -e "${MAGENTA}──────────────────────────────────────────────────────────────────────────────${NC}"
    echo -e "${YELLOW}${BOLD} HERRAMIENTAS Y UTILIDADES ${NC}"
    echo -e "${CYAN}${BOLD} 7)${NC}  ${WHITE}Gestionar archivo .pgpass${NC}"
    echo -e "${CYAN}${BOLD} 8)${NC}  ${WHITE}Eliminar backups manualmente${NC}"
    echo -e "${CYAN}${BOLD} 9)${NC}  ${WHITE}Mostrar resumen de backups recientes${NC}"

    # Sección: Exportar y Restaurar (Ad-hoc)
    echo -e "${MAGENTA}──────────────────────────────────────────────────────────────────────────────${NC}"
    echo -e "${YELLOW}${BOLD} OPERACIONES AD-HOC ${NC}"
    echo -e "${CYAN}${BOLD}10)${NC}  ${WHITE}Exportar base de datos ad hoc${NC}"
    echo -e "${CYAN}${BOLD}11)${NC}  ${WHITE}Restaurar backup ad hoc${NC}"

    # Sección: Configuración global y Salir
    echo -e "${MAGENTA}──────────────────────────────────────────────────────────────────────────────${NC}"
    echo -e "${YELLOW}${BOLD} AJUSTES GENERALES ${NC}"
    echo -e "${CYAN}${BOLD}12)${NC}  ${WHITE}Editar configuración global${NC}"
    echo -e "${CYAN}${BOLD} 0)${NC}  ${WHITE}Salir${NC}"

    echo -e "${MAGENTA}${BOLD}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
}


edit_globals_menu() {
    load_globals
    echo -e "${MAGENTA}${BOLD}╔════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}${BOLD}║${WHITE}${BOLD}        CONFIGURACIÓN GLOBAL DE BACKUP      ${MAGENTA}${BOLD}║${NC}"
    echo -e "${MAGENTA}${BOLD}╠════════════════════════════════════════════╣${NC}"

    read -p "Ruta base backups [$DEFAULT_BACKUPS_DIR]: " new
    [[ -n "$new" ]] && DEFAULT_BACKUPS_DIR="$new"

    read -p "Ruta de logs [$LOG_DIR]: " new
    [[ -n "$new" ]] && LOG_DIR="$new"

    read -p "Ruta de configuraciones [$CONFIG_DIR]: " new
    [[ -n "$new" ]] && CONFIG_DIR="$new"

    read -p "Timeout de backup en segundos [$TIMEOUT]: " new
    [[ -n "$new" && "$new" =~ ^[0-9]+$ ]] && TIMEOUT="$new"

    save_globals

    # VUELVE A RECARGAR VARIABLES Y RUTAS DESPUÉS DE GUARDAR
    load_globals
    DEFAULT_BACKUPS_DIR="${DEFAULT_BACKUPS_DIR:-${HOME}/pg_backup/backups}"
    LOG_DIR="${LOG_DIR:-${DEFAULT_BACKUPS_DIR}/logs}"
    CONFIG_DIR="${CONFIG_DIR:-${DEFAULT_BACKUPS_DIR}/config}"
    CONFIG_FILE="${CONFIG_DIR}/pg_backup_config.json"
    TIMEOUT="${TIMEOUT:-900}"
    mkdir -p "$DEFAULT_BACKUPS_DIR" "$LOG_DIR" "$CONFIG_DIR"

    read -p "ENTER para continuar..."
}


gestion_configuraciones_menu() {
    while true; do
        clear
        echo -e "${MAGENTA}${BOLD}╔════════════════════════════════════════════════════╗${NC}"
        echo -e "${MAGENTA}${BOLD}║${WHITE}${BOLD}         GESTIÓN DE CONFIGURACIONES DE BACKUP        ${MAGENTA}${BOLD}║${NC}"
        echo -e "${MAGENTA}${BOLD}╠════════════════════════════════════════════════════╣${NC}"
        echo -e "${CYAN}${BOLD}1)${NC} ${WHITE}Añadir nueva configuración${NC}"
        echo -e "${CYAN}${BOLD}2)${NC} ${WHITE}Editar configuración existente${NC}"
        echo -e "${CYAN}${BOLD}3)${NC} ${WHITE}Eliminar configuración${NC}"
        echo -e "${CYAN}${BOLD}4)${NC} ${WHITE}Listar configuraciones actuales${NC}"
        echo -e "${CYAN}${BOLD}0)${NC} ${WHITE}Volver${NC}"
        read -p "Seleccione opción: " op
        case "$op" in
            1) add_entry ;;
            2) edit_entry ;;
            3) delete_entry ;;
            4) print_entries; read -p "ENTER para continuar..." ;;
            0) break ;;
            *) echo_warn "Opción inválida"; sleep 1 ;;
        esac
    done
}

main_menu() {
    clear
    echo -e "${MAGENTA}${BOLD}╔════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}${BOLD}║${WHITE}${BOLD}         BACKUP POSTGRESQL           ${MAGENTA}${BOLD}║${NC}"
    echo -e "${MAGENTA}${BOLD}╠════════════════════════════════════╣${NC}"
    echo -e "${CYAN}${BOLD}1)${NC} ${WHITE}Forzar ejecución de todos los backups${NC}"
    echo -e "${CYAN}${BOLD}2)${NC} ${WHITE}Ejecutar backups según calendario${NC}"
    echo -e "${CYAN}${BOLD}3)${NC} ${WHITE}Gestionar configuraciones${NC}"
    echo -e "${CYAN}${BOLD}4)${NC} ${WHITE}Gestionar archivo .pgpass${NC}"
    echo -e "${CYAN}${BOLD}5)${NC} ${WHITE}Exportar base de datos ad hoc${NC}"
    echo -e "${CYAN}${BOLD}6)${NC} ${WHITE}Restaurar backup ad hoc${NC}"
    echo -e "${CYAN}${BOLD}7)${NC} ${WHITE}Eliminar backups manualmente${NC}"
    echo -e "${CYAN}${BOLD}8)${NC} ${WHITE}Mostrar resumen de backups recientes${NC}"
    echo -e "${CYAN}${BOLD}9)${NC} ${WHITE}Editar configuración global${NC}"
    echo -e "${CYAN}${BOLD}0)${NC} ${WHITE}Salir${NC}"
}

CONFIG_FILE="${CONFIG_DIR}/pg_backup_config.json"

mkdir -p "$DEFAULT_BACKUPS_DIR" "$LOG_DIR" "$CONFIG_DIR"
load_globals
load_config

###############################################################################
# PARÁMETROS EN LÍNEA DE COMANDOS  (inserta este bloque antes del while true) #
###############################################################################
case "$1" in
    --run-backups)      # ejecuta backups según calendario
        run_all_backups
        exit $? ;;      # salimos sin mostrar menú
    --force-backups)    # ejecuta TODOS los backups, ignore calendario
        run_all_backups_force
        exit $? ;;
    --help|-h)          # ayuda rápida
        echo "Uso: $0 [--run-backups | --force-backups | --help]"
        echo "  --run-backups    Ejecuta los backups programados y sale."
        echo "  --force-backups  Ejecuta todos los backups (ignora frecuencia) y sale."
        echo "  --help, -h       Muestra esta ayuda."
        exit 0 ;;
    "" ) ;;             # sin argumentos ⇒ dejar que caiga al menú
    *  ) echo "[ERROR] Opción no reconocida: $1"; exit 1 ;;
esac

# Si el script viene de cron (no hay TTY) y no nos dieron argumento válido, abortamos.
if [[ ! -t 0 ]]; then
    echo "[ERROR] Ejecución no interactiva sin opción (--run-backups / --force-backups)."
    exit 1
fi
###############################################################################

while true; do
    main_menu_unificado
    read -p "Selecciona opción: " opt
    case "$opt" in
        1) run_all_backups_force; read -p "ENTER para continuar..." ;;
        2) run_all_backups; read -p "ENTER para continuar..." ;;
        3) add_entry ;;
        4) edit_entry ;;
        5) delete_entry ;;
        6) print_entries; read -p "ENTER para continuar..." ;;
        7) pgpass_menu ;;
        8) eliminar_backups_manualmente; read -p "ENTER para continuar..." ;;
        9) show_backup_summary; read -p "ENTER para continuar..." ;;
       10) export_single_bd_ad_hoc; read -p "ENTER para continuar..." ;;
       11) restore_single_bd_ad_hoc; read -p "ENTER para continuar..." ;;
       12) edit_globals_menu ;;
        0) echo "Saliendo..."; break ;;
        *) echo_warn "Opción inválida"; sleep 1 ;;
    esac
done

