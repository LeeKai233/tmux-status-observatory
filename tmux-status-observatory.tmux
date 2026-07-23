#!/usr/bin/env bash

set -u

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
RENDERER="$ROOT_DIR/bin/tmux-status-observatory"
ANIMATOR="$ROOT_DIR/bin/tmux-status-sweep"

if [[ ! -x "$RENDERER" ]]; then
    printf 'tmux-status-observatory: renderer is not executable: %s\n' "$RENDERER" >&2
    exit 1
fi

shell_quote() {
    printf '%q' "$1"
}

global_option_or_default() {
    local option=$1 default=$2 value
    value=$(tmux show-option -gqv "$option" 2>/dev/null || true)
    printf '%s' "${value:-$default}"
}

reset_session_runtime() {
    local session option kind
    local -a options=(
        @status_plain_ready
        @status_sweep_active
        @status_sweep_token
        @status_animation_kind
        @status_animation_pid
        @status_forecast_transition_pending
        @status_plain_frame_narrow
        @status_plain_frame_medium
        @status_plain_frame_wide
        @status_sweep_frame_narrow
        @status_sweep_frame_medium
        @status_sweep_frame_wide
        @status_forecast_left_narrow
        @status_forecast_left_medium
        @status_forecast_left_wide
        @status_forecast_right_narrow
        @status_forecast_right_medium
        @status_forecast_right_wide
    )
    while IFS= read -r session; do
        kind=$(tmux show-option -qv -t "$session" @status_animation_kind 2>/dev/null || true)
        if [[ "$kind" == sweep || "$kind" == forecast ]]; then
            "$ANIMATOR" stop --session "$session" --kind "$kind" >/dev/null 2>&1 || true
        fi
        for option in "${options[@]}"; do
            tmux set-option -qu -t "$session" "$option" 2>/dev/null || true
        done
    done < <(tmux list-sessions -F '#{session_id}' 2>/dev/null || true)
}

renderer_command=$(shell_quote "$RENDERER")

reset_session_runtime

plain_frames='#{?#{>=:#{client_width},180},#{E:@status_plain_frame_wide},#{?#{>=:#{client_width},120},#{E:@status_plain_frame_medium},#{E:@status_plain_frame_narrow}}}'
sweep_frames='#{?#{>=:#{client_width},180},#{E:@status_sweep_frame_wide},#{?#{>=:#{client_width},120},#{E:@status_sweep_frame_medium},#{E:@status_sweep_frame_narrow}}}'
forecast_frames='#{?#{>=:#{client_width},180},#{E:@status_forecast_left_wide}#{E:@status_forecast_right_wide},#{?#{>=:#{client_width},120},#{E:@status_forecast_left_medium}#{E:@status_forecast_right_medium},#{E:@status_forecast_left_narrow}#{E:@status_forecast_right_narrow}}}'
forecast_toggle_command="$renderer_command --toggle-forecast '#{session_id}' #{client_width}"

status_right="#{?#{==:#{@status_animation_kind},forecast},$forecast_frames,#{?#{==:#{@status_animation_kind},sweep},$sweep_frames,#{?#{@status_plain_ready},$plain_frames,#($renderer_command --status '#{session_id}' #{client_width})}}}#{?#{@status_animation_kind},,#{?#{@status_forecast_transition_pending},,#($renderer_command --status '#{session_id}' #{client_width} >/dev/null 2>&1)}} "

tmux set-option -g status-style 'bg=#26a269,fg=black'
tmux set-option -g status-left-length 24
tmux set-option -g status-left '[#{=20:session_name}] '
tmux set-option -g status-right-length 240
tmux set-option -g status-interval 1
tmux set-option -g status-right "$status_right"

tmux set-option -gu @status_mode
tmux set-option -gu @status_sweep_started
tmux set-option -gu @status_palette
tmux set-option -gu @status_sweep_peak
tmux set-option -g @status_sweep_fps "$(global_option_or_default @status_sweep_fps 30)"
tmux set-option -g @status_sweep_speed "$(global_option_or_default @status_sweep_speed 30)"
tmux set-option -g @status_sweep_half_width "$(global_option_or_default @status_sweep_half_width 10)"
tmux set-option -g @status_forecast_transition_fps "$(global_option_or_default @status_forecast_transition_fps 60)"
tmux set-option -g @status_forecast_transition_duration "$(global_option_or_default @status_forecast_transition_duration 0.55)"

tmux bind-key a run-shell -b "$renderer_command --sweep '#{session_id}'"
tmux bind-key W run-shell -b "$forecast_toggle_command"
tmux bind-key -n MouseDown1Status \
    if-shell -F '#{==:#{mouse_status_range},weather}' \
    "run-shell -b \"$forecast_toggle_command\"" \
    'switch-client -t ='
tmux unbind-key g
