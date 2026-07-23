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
if [[ "${TMUX_STATUS_SKIP_RELOAD:-0}" != 1 ]] && tmux list-sessions >/dev/null 2>&1; then
    tmux run-shell "$ROOT_DIR/tmux-status-observatory.tmux"
    printf 'Loaded tmux-status-observatory into the running tmux server.\n'
else
    printf 'The configuration will load when tmux starts.\n'
fi
printf 'Next: edit %s and set your location and QWeather API key.\n' "$ENV_FILE"
