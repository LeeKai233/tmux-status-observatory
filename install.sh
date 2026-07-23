#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
TMUX_CONFIG="${TMUX_STATUS_TMUX_CONFIG:-}"
ENV_FILE="${TMUX_STATUS_CONFIG:-$CONFIG_HOME/tmux/status.env}"
MARK_START='# >>> tmux-status-observatory >>>'
MARK_END='# <<< tmux-status-observatory <<<'

usage() {
    printf 'Usage: %s [--dry-run]\n' "${0##*/}"
    printf '       %s --uninstall [--dry-run]\n' "${0##*/}"
    printf '       %s --no-auto-location\n' "${0##*/}"
}

AUTO_LOCATION_URL='https://ipwho.is/?fields=success,message,city,region,country_code,latitude,longitude'
CURL_BIN=${CURL_BIN:-curl}
AUTO_LOCATION=1

config_value() {
    local key=$1
    [[ -r "$ENV_FILE" ]] || return 0
    (
        set +u
        # shellcheck disable=SC1090
        source "$ENV_FILE"
        printf '%s' "${!key-}"
    )
}

coordinates_valid() {
    [[ "$1" =~ ^-?[0-9]+([.][0-9]+)?$ && "$2" =~ ^-?[0-9]+([.][0-9]+)?$ ]]
}

write_env_values() {
    local temp key1 value1 key2 value2 key3 value3
    key1=$1
    value1=$2
    key2=${3:-}
    value2=${4:-}
    key3=${5:-}
    value3=${6:-}
    temp=$(mktemp "${ENV_FILE}.tmp.XXXXXX")

    awk -v key1="$key1" -v value1="$value1" -v key2="$key2" -v value2="$value2" -v key3="$key3" -v value3="$value3" '
        function assignment(key, value) { return key "=\"" value "\"" }
        $0 ~ "^[[:space:]]*" key1 "[[:space:]]*=" {
            print assignment(key1, value1)
            found1 = 1
            next
        }
        key2 != "" && $0 ~ "^[[:space:]]*" key2 "[[:space:]]*=" {
            print assignment(key2, value2)
            found2 = 1
            next
        }
        key3 != "" && $0 ~ "^[[:space:]]*" key3 "[[:space:]]*=" {
            print assignment(key3, value3)
            found3 = 1
            next
        }
        { print }
        END {
            if (!found1) print assignment(key1, value1)
            if (key2 != "" && !found2) print assignment(key2, value2)
            if (key3 != "" && !found3) print assignment(key3, value3)
        }
    ' "$ENV_FILE" >"$temp"

    if cmp -s "$temp" "$ENV_FILE"; then
        rm -f -- "$temp"
        return 0
    fi

    local backup
    backup="${ENV_FILE}.tmux-status-observatory.$(date +%Y%m%d%H%M%S).bak"
    cp -p -- "$ENV_FILE" "$backup"
    chmod 600 "$backup" 2>/dev/null || true
    mv -f -- "$temp" "$ENV_FILE"
    chmod 600 "$ENV_FILE" 2>/dev/null || true
    printf 'Updated user config: %s (backup: %s)\n' "$ENV_FILE" "$backup"
}

detect_location() {
    local response latitude longitude
    response=$(mktemp "${TMPDIR:-/tmp}/tmux-status-observatory-location.XXXXXX")
    if ! "$CURL_BIN" --fail --silent --show-error --location --compressed \
        --connect-timeout 4 --max-time 10 "$AUTO_LOCATION_URL" >"$response" 2>/dev/null; then
        rm -f -- "$response"
        return 1
    fi

    if ! jq -e '
        .success == true
        and (.latitude | type == "number")
        and (.longitude | type == "number")
        and (.latitude >= -90 and .latitude <= 90)
        and (.longitude >= -180 and .longitude <= 180)
    ' "$response" >/dev/null 2>&1; then
        rm -f -- "$response"
        return 1
    fi

    latitude=$(jq -r '.latitude' "$response")
    longitude=$(jq -r '.longitude' "$response")
    rm -f -- "$response"
    printf '%s\t%s\n' "$longitude" "$latitude"
}

auto_configure_location() {
    local current_label current_longitude current_latitude detected longitude latitude label_placeholder=0
    (( AUTO_LOCATION )) || return 0

    current_label=$(config_value STATUS_LOCATION_LABEL)
    current_longitude=$(config_value STATUS_LONGITUDE)
    current_latitude=$(config_value STATUS_LATITUDE)

    if [[ "$current_label" == 'Your City' ]]; then
        label_placeholder=1
        current_label=''
    fi
    if coordinates_valid "$current_longitude" "$current_latitude"; then
        (( label_placeholder )) && write_env_values STATUS_LOCATION_LABEL ''
        return 0
    fi

    if ! detected=$(detect_location); then
        printf 'Location auto-detection failed; kept %s unchanged.\n' "$ENV_FILE" >&2
        printf 'Set STATUS_LONGITUDE and STATUS_LATITUDE manually, or rerun without --no-auto-location.\n' >&2
        return 0
    fi
    IFS=$'\t' read -r longitude latitude <<<"$detected"
    if (( label_placeholder )); then
        write_env_values STATUS_LOCATION_LABEL '' STATUS_LONGITUDE "$longitude" STATUS_LATITUDE "$latitude"
    else
        write_env_values STATUS_LONGITUDE "$longitude" STATUS_LATITUDE "$latitude"
    fi
    printf 'Auto-detected approximate coordinates: %s, %s\n' "$longitude" "$latitude"
}

print_credential_help() {
    local qweather_host qweather_key nasa_key
    qweather_host=$(config_value QWEATHER_API_HOST)
    qweather_key=$(config_value QWEATHER_API_KEY)
    nasa_key=$(config_value NASA_API_KEY)
    if [[ -z "$qweather_host" || -z "$qweather_key" ]]; then
        printf '\nQWeather setup:\n'
        printf '  Create a project and API KEY: https://console.qweather.com/project\n'
        printf '  Copy your private API Host: https://console.qweather.com/setting\n'
        printf '  Official setup guide: https://dev.qweather.com/docs/configuration/project-and-key/\n'
        printf '  Store QWEATHER_API_HOST and QWEATHER_API_KEY in %s\n' "$ENV_FILE"
    fi
    if [[ -z "$nasa_key" || "$nasa_key" == DEMO_KEY ]]; then
        printf '\nNASA setup (optional; DEMO_KEY remains available):\n'
        printf '  Request a personal key: https://api.nasa.gov/#signUp\n'
        printf '  Store NASA_API_KEY in %s\n' "$ENV_FILE"
    fi
}

tmux_quote() {
    local value=$1
    value=${value//\'/\'\\\'\'}
    printf "'%s'" "$value"
}

choose_tmux_config() {
    [[ -n "$TMUX_CONFIG" ]] && return 0
    if [[ -f "$HOME/.tmux.conf" ]]; then
        TMUX_CONFIG="$HOME/.tmux.conf"
    elif [[ -f "$CONFIG_HOME/tmux/tmux.conf" ]]; then
        TMUX_CONFIG="$CONFIG_HOME/tmux/tmux.conf"
    else
        TMUX_CONFIG="$CONFIG_HOME/tmux/tmux.conf"
    fi
}

config_block() {
    printf '%s\n' "$MARK_START"
    printf 'run-shell %s\n' "$(tmux_quote "$ROOT_DIR/tmux-status-observatory.tmux")"
    printf '%s\n' "$MARK_END"
}

strip_block() {
    local source=$1 target=$2
    awk -v start="$MARK_START" -v end="$MARK_END" '
        $0 == start { inside = 1; found = 1; next }
        $0 == end { inside = 0; next }
        !inside { print }
        END { if (inside) exit 2 }
    ' "$source" >"$target"
}

validate_config() {
    local config=$1 socket="tmux-status-observatory-check-$$"
    tmux -L "$socket" -f /dev/null new-session -d -s check >/dev/null 2>&1 || true
    if ! tmux -L "$socket" source-file -n "$config" >/dev/null 2>&1; then
        tmux -L "$socket" kill-server >/dev/null 2>&1 || true
        return 1
    fi
    tmux -L "$socket" kill-server >/dev/null 2>&1 || true
}

write_install_block() {
    local temp backup
    mkdir -p "$(dirname -- "$TMUX_CONFIG")"
    temp=$(mktemp "${TMUX_CONFIG}.tmp.XXXXXX")
    if [[ -e "$TMUX_CONFIG" ]]; then
        strip_block "$TMUX_CONFIG" "$temp"
    else
        : >"$temp"
    fi
    if [[ -s "$temp" ]]; then
        printf '\n' >>"$temp"
    fi
    config_block >>"$temp"
    validate_config "$temp" || {
        rm -f -- "$temp"
        printf 'tmux-status-observatory: refusing invalid tmux config: %s\n' "$TMUX_CONFIG" >&2
        return 1
    }
    if [[ -e "$TMUX_CONFIG" ]] && cmp -s "$temp" "$TMUX_CONFIG"; then
        rm -f -- "$temp"
        return 0
    fi
    if [[ -e "$TMUX_CONFIG" ]]; then
        backup="$TMUX_CONFIG.tmux-status-observatory.$(date +%Y%m%d%H%M%S).bak"
        cp -p -- "$TMUX_CONFIG" "$backup"
        printf 'Backed up tmux config to %s\n' "$backup"
    fi
    mv -f -- "$temp" "$TMUX_CONFIG"
    chmod 600 "$TMUX_CONFIG" 2>/dev/null || true
}

write_env_template() {
    mkdir -p "$(dirname -- "$ENV_FILE")"
    if [[ ! -e "$ENV_FILE" ]]; then
        install -m 600 "$ROOT_DIR/config/status.env.example" "$ENV_FILE"
        printf 'Created user config: %s\n' "$ENV_FILE"
    else
        chmod 600 "$ENV_FILE" 2>/dev/null || true
        printf 'Kept existing user config: %s\n' "$ENV_FILE"
    fi
}

uninstall_block() {
    local temp backup
    choose_tmux_config
    [[ -e "$TMUX_CONFIG" ]] || return 0
    temp=$(mktemp "${TMUX_CONFIG}.tmp.XXXXXX")
    strip_block "$TMUX_CONFIG" "$temp"
    if cmp -s "$temp" "$TMUX_CONFIG"; then
        rm -f -- "$temp"
        printf 'No tmux-status-observatory block found in %s\n' "$TMUX_CONFIG"
        return 0
    fi
    backup="$TMUX_CONFIG.tmux-status-observatory.$(date +%Y%m%d%H%M%S).bak"
    cp -p -- "$TMUX_CONFIG" "$backup"
    mv -f -- "$temp" "$TMUX_CONFIG"
    printf 'Removed block from %s (backup: %s)\n' "$TMUX_CONFIG" "$backup"
}

dry_run=0
uninstall=0
while (($#)); do
    case "$1" in
        --dry-run) dry_run=1 ;;
        --uninstall) uninstall=1 ;;
        --no-auto-location) AUTO_LOCATION=0 ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
    shift
done

choose_tmux_config
if (( uninstall )); then
    if (( dry_run )); then
        printf 'Would remove the marked block from %s\n' "$TMUX_CONFIG"
    else
        uninstall_block
    fi
    exit 0
fi

if (( dry_run )); then
    printf 'Would install tmux entrypoint from %s\n' "$ROOT_DIR"
    printf 'Would update tmux config: %s\n' "$TMUX_CONFIG"
    printf 'Would create user config if absent: %s\n' "$ENV_FILE"
    exit 0
fi

write_install_block
write_env_template
auto_configure_location
if [[ "${TMUX_STATUS_SKIP_RELOAD:-0}" != 1 ]] && tmux list-sessions >/dev/null 2>&1; then
    tmux run-shell "$ROOT_DIR/tmux-status-observatory.tmux"
    printf 'Loaded tmux-status-observatory into the running tmux server.\n'
else
    printf 'The configuration will load when tmux starts.\n'
fi
printf 'Next: edit %s and set your QWeather API Host and API key.\n' "$ENV_FILE"
print_credential_help
