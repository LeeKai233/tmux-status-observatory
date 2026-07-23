#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
RENDERER="$ROOT_DIR/bin/tmux-status-observatory"
TMUX_CONFIG_SCRIPT="$ROOT_DIR/tmux-status-observatory.tmux"
ASCIINEMA_BIN=${ASCIINEMA:-asciinema}
AGG_BIN=${AGG:-agg}
STATUS_CONFIG=${TMUX_STATUS_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/tmux/status.env}
CACHE_HOME=${XDG_CACHE_HOME:-$HOME/.cache}
OUTPUT=${TMUX_STATUS_DEMO_OUTPUT:-$ROOT_DIR/assets/tmux-status-observatory.gif}
WIDTH=${TMUX_STATUS_DEMO_COLS:-200}
HEIGHT=${TMUX_STATUS_DEMO_ROWS:-3}
SESSION=observatory-demo
SOCKET="tmux-status-observatory-demo-$$"

shell_quote() {
    printf '%q' "$1"
}

cleanup() {
    set +e
    tmux -L "$SOCKET" kill-server >/dev/null 2>&1 || true
    rm -rf -- "$WORK_DIR"
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || {
        printf 'record-demo: missing required command: %s\n' "$1" >&2
        exit 1
    }
}

if [[ ! -x "$RENDERER" ]]; then
    printf 'record-demo: renderer is not executable: %s\n' "$RENDERER" >&2
    exit 1
fi
if [[ ! -x "$ROOT_DIR/bin/tmux-status-sweep" ]]; then
    printf 'record-demo: sweep renderer is not executable: %s\n' "$ROOT_DIR/bin/tmux-status-sweep" >&2
    exit 1
fi
if [[ ! -t 0 || ! -t 1 ]]; then
    printf 'record-demo: run this target from an interactive terminal.\n' >&2
    exit 1
fi
if [[ ! "$WIDTH" =~ ^[0-9]+$ || ! "$HEIGHT" =~ ^[0-9]+$ ]]; then
    printf 'record-demo: TMUX_STATUS_DEMO_COLS and TMUX_STATUS_DEMO_ROWS must be integers.\n' >&2
    exit 1
fi

require_command "$ASCIINEMA_BIN"
require_command "$AGG_BIN"
require_command tmux

WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/tmux-status-observatory-demo.XXXXXX")
CAST_FILE="$WORK_DIR/tmux-status-observatory.cast"
GIF_FILE="$WORK_DIR/tmux-status-observatory.gif"
trap cleanup EXIT INT TERM

mkdir -p "$CACHE_HOME/tmux-status" "$(dirname -- "$OUTPUT")"
chmod 700 "$CACHE_HOME/tmux-status" 2>/dev/null || true

# Refresh the user's current cache before starting the isolated tmux server.
env -u TMUX TERM=xterm-256color \
    TMUX_STATUS_CONFIG="$STATUS_CONFIG" \
    XDG_CACHE_HOME="$CACHE_HOME" \
    "$RENDERER" --refresh >/dev/null

tmux -L "$SOCKET" -f /dev/null new-session -d \
    -s "$SESSION" -n observatory -x "$WIDTH" -y "$HEIGHT" 'sleep 3600'
tmux -L "$SOCKET" set-environment -g TMUX_STATUS_CONFIG "$STATUS_CONFIG"
tmux -L "$SOCKET" set-environment -g XDG_CACHE_HOME "$CACHE_HOME"
tmux -L "$SOCKET" set-environment -g TMUX_STATUS_SWEEP_RENDERER "$ROOT_DIR/bin/tmux-status-sweep"
tmux -L "$SOCKET" set-environment -t "$SESSION" TMUX_STATUS_CONFIG "$STATUS_CONFIG"
tmux -L "$SOCKET" set-environment -t "$SESSION" XDG_CACHE_HOME "$CACHE_HOME"
tmux -L "$SOCKET" set-environment -t "$SESSION" TMUX_STATUS_SWEEP_RENDERER "$ROOT_DIR/bin/tmux-status-sweep"

tmux -L "$SOCKET" run-shell -b "$TMUX_CONFIG_SCRIPT"
for _ in {1..50}; do
    if [[ -n "$(tmux -L "$SOCKET" show-option -gqv status-right 2>/dev/null || true)" ]]; then
        break
    fi
    sleep 0.1
done

SESSION_ID=$(tmux -L "$SOCKET" display-message -p -t "$SESSION" '#{session_id}')
SESSION_KEY=$(printf '%s' "$SESSION_ID" | tr -c '[:alnum:]_.-' '_')
printf '%s\n' "$(date +%Y%m%d%H%M)" >"$CACHE_HOME/tmux-status/auto-sweep-$SESSION_KEY.stamp"

RENDERER_COMMAND=$(shell_quote "$RENDERER")
SESSION_ARGUMENT=$(shell_quote "$SESSION_ID")

tmux -L "$SOCKET" run-shell -b \
    "$RENDERER_COMMAND --status $SESSION_ARGUMENT $WIDTH 0 >/dev/null 2>&1"
for _ in {1..100}; do
    if [[ "$(tmux -L "$SOCKET" show-option -qv -t "$SESSION" @status_plain_ready 2>/dev/null || true)" == 1 ]]; then
        break
    fi
    sleep 0.1
done

mapfile -d '' -t PLAIN_FRAMES < <(
    env -u TMUX TERM=xterm-256color \
        TMUX_STATUS_CONFIG="$STATUS_CONFIG" \
        XDG_CACHE_HOME="$CACHE_HOME" \
        "$RENDERER" --plain-set 0
)
if (( ${#PLAIN_FRAMES[@]} < 3 )); then
    printf 'record-demo: failed to render a final plain frame.\n' >&2
    exit 1
fi
FINAL_STATUS="[observatory-demo] 0:observatory* ${PLAIN_FRAMES[2]}"
FINAL_STATUS_ARGUMENT=$(shell_quote "$FINAL_STATUS")
ATTACH_COMMAND="tmux -L $(shell_quote "$SOCKET") attach-session -t $(shell_quote "$SESSION"); printf '\\033[2J\\033[H\\n\\n\\033[30;48;2;38;162;105m%s\\033[K\\033[0m' $FINAL_STATUS_ARGUMENT; sleep 0.2"
env -u TMUX TERM=xterm-256color \
    "$ASCIINEMA_BIN" rec --quiet --overwrite \
    --cols "$WIDTH" --rows "$HEIGHT" --idle-time-limit 2 \
    --command "$ATTACH_COMMAND" "$CAST_FILE" &
RECORD_PID=$!

CLIENT_TTY=''
for _ in {1..100}; do
    CLIENT_TTY=$(tmux -L "$SOCKET" list-clients -F '#{client_name}' 2>/dev/null | head -n 1 || true)
    [[ -n "$CLIENT_TTY" ]] && break
    sleep 0.1
done
if [[ -z "$CLIENT_TTY" ]]; then
    kill "$RECORD_PID" 2>/dev/null || true
    wait "$RECORD_PID" 2>/dev/null || true
    printf 'record-demo: isolated tmux client did not attach.\n' >&2
    exit 1
fi

wait_for_animation() {
    local expected=$1 kind seen=0
    for _ in {1..400}; do
        kind=$(tmux -L "$SOCKET" show-option -qv -t "$SESSION" @status_animation_kind 2>/dev/null || true)
        if [[ "$kind" == "$expected" ]]; then
            seen=1
        elif (( seen )) && [[ -z "$kind" ]]; then
            return 0
        fi
        sleep 0.05
    done
    printf 'record-demo: timed out waiting for %s animation.\n' "$expected" >&2
    return 1
}

# Keep each state long enough to be readable, and wait for both animations to finish.
sleep 1
tmux -L "$SOCKET" run-shell -b "$RENDERER_COMMAND --toggle-forecast $SESSION_ARGUMENT $WIDTH >/dev/null 2>&1"
wait_for_animation forecast
sleep 0.8
tmux -L "$SOCKET" run-shell -b "$RENDERER_COMMAND --sweep $SESSION_ARGUMENT >/dev/null 2>&1"
wait_for_animation sweep
sleep 0.5
tmux -L "$SOCKET" run-shell -b "$RENDERER_COMMAND --toggle-forecast $SESSION_ARGUMENT $WIDTH >/dev/null 2>&1"
wait_for_animation forecast
sleep 0.9

CLIENT_TTY=$(tmux -L "$SOCKET" list-clients -F '#{client_name}' 2>/dev/null | head -n 1 || true)
[[ -n "$CLIENT_TTY" ]] && tmux -L "$SOCKET" detach-client -E 'exec true' -t "$CLIENT_TTY"
wait "$RECORD_PID"

[[ -s "$CAST_FILE" ]] || {
    printf 'record-demo: asciinema did not produce a cast file.\n' >&2
    exit 1
}

"$AGG_BIN" --quiet \
    --font-family 'Noto Sans Mono CJK SC' \
    --font-size 16 \
    --line-height 1.2 \
    --theme github-dark \
    --fps-cap 30 \
    --idle-time-limit 2 \
    --last-frame-duration 1 \
    --cols "$WIDTH" --rows "$HEIGHT" \
    "$CAST_FILE" "$GIF_FILE"

mv -f -- "$GIF_FILE" "$OUTPUT"
printf 'Recorded %s\n' "$OUTPUT"
