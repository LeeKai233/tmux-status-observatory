#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SOCKET="tmux-status-observatory-binding-check-$$"

cleanup() {
    tmux -L "$SOCKET" kill-server >/dev/null 2>&1 || true
}
trap cleanup EXIT

tmux -L "$SOCKET" -f /dev/null new-session -d -s check >/dev/null
server_pid=$(tmux -L "$SOCKET" display-message -p '#{pid}')
socket_path=$(tmux -L "$SOCKET" display-message -p '#{socket_path}')
export TMUX="$socket_path,$server_pid,0"

"$ROOT_DIR/tmux-status-observatory.tmux"

binding=$(tmux list-keys -T root MouseDown1Status)
renderer_command=$(printf '%q' "$ROOT_DIR/bin/tmux-status-observatory")
expected="run-shell -b \\\"$renderer_command --toggle-forecast '#{session_id}' #{client_width}\\\""
[[ "$binding" == *"$expected"* ]]

broken=$(tmux if-shell -F 1 'run-shell -b /bin/true one two' '' 2>&1 || true)
[[ "$broken" == *"too many arguments"* ]]

safe=$(tmux if-shell -F 1 'run-shell -b "/bin/true one two"' '' 2>&1 || true)
[[ -z "$safe" ]]

printf 'tmux mouse binding verification: PASS\n'
