#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/tmux-status-observatory-install.XXXXXX")
FAKE_CURL="$ROOT_DIR/tests/fixtures/fake-location-curl"
trap 'rm -rf -- "$TEST_ROOT"' EXIT

assert_contains() {
    local needle=$1 file=$2
    grep -F -- "$needle" "$file" >/dev/null
}

assert_not_contains() {
    local needle=$1 file=$2
    ! grep -F -- "$needle" "$file" >/dev/null
}

setup_case() {
    local name=$1
    CASE_ROOT="$TEST_ROOT/$name"
    mkdir -p "$CASE_ROOT/home" "$CASE_ROOT/config/tmux"
    CONFIG_FILE="$CASE_ROOT/config/tmux/status.env"
    TMUX_FILE="$CASE_ROOT/tmux.conf"
    CURL_LOG="$CASE_ROOT/curl.log"
    OUTPUT_FILE="$CASE_ROOT/output.log"
    export HOME="$CASE_ROOT/home"
    export XDG_CONFIG_HOME="$CASE_ROOT/config"
    export TMUX_STATUS_CONFIG="$CONFIG_FILE"
    export TMUX_STATUS_TMUX_CONFIG="$TMUX_FILE"
    export TMUX_STATUS_SKIP_RELOAD=1
    export CURL_BIN="$FAKE_CURL"
    export FAKE_CURL_LOG="$CURL_LOG"
    unset FAKE_LOCATION_MODE
}

run_install() {
    "$ROOT_DIR/install.sh" "$@" >"$OUTPUT_FILE" 2>&1
}

set_config_value() {
    local key=$1 value=$2
    sed -i "s|^${key}=.*|${key}=\"${value}\"|" "$CONFIG_FILE"
}

setup_case blank
run_install
assert_contains 'STATUS_LONGITUDE="104.16022"' "$CONFIG_FILE"
assert_contains 'STATUS_LATITUDE="30.82422"' "$CONFIG_FILE"
assert_contains 'Auto-detected approximate coordinates: 104.16022, 30.82422' "$OUTPUT_FILE"
[[ "$(stat -c '%a' "$CONFIG_FILE")" == 600 ]]
[[ -s "$CURL_LOG" ]]

setup_case manual
cp "$ROOT_DIR/config/status.env.example" "$CONFIG_FILE"
set_config_value STATUS_LONGITUDE 121.4737
set_config_value STATUS_LATITUDE 31.2304
set_config_value QWEATHER_API_KEY existing-secret
run_install
assert_contains 'STATUS_LONGITUDE="121.4737"' "$CONFIG_FILE"
assert_contains 'STATUS_LATITUDE="31.2304"' "$CONFIG_FILE"
[[ ! -e "$CURL_LOG" ]]
assert_not_contains existing-secret "$OUTPUT_FILE"

setup_case opt_out
run_install --no-auto-location
assert_contains 'STATUS_LONGITUDE=""' "$CONFIG_FILE"
assert_contains 'STATUS_LATITUDE=""' "$CONFIG_FILE"
[[ ! -e "$CURL_LOG" ]]

setup_case malformed
export FAKE_LOCATION_MODE=invalid
run_install
assert_contains 'Location auto-detection failed' "$OUTPUT_FILE"
assert_contains 'STATUS_LONGITUDE=""' "$CONFIG_FILE"
assert_contains 'STATUS_LATITUDE=""' "$CONFIG_FILE"

setup_case failed
export FAKE_LOCATION_MODE=fail
run_install
assert_contains 'Location auto-detection failed' "$OUTPUT_FILE"
assert_contains 'STATUS_LONGITUDE=""' "$CONFIG_FILE"
assert_contains 'STATUS_LATITUDE=""' "$CONFIG_FILE"

setup_case placeholder
cp "$ROOT_DIR/config/status.env.example" "$CONFIG_FILE"
set_config_value STATUS_LOCATION_LABEL 'Your City'
set_config_value STATUS_LONGITUDE 121.4737
set_config_value STATUS_LATITUDE 31.2304
run_install
assert_contains 'STATUS_LOCATION_LABEL=""' "$CONFIG_FILE"
backup_count=$(find "$(dirname -- "$CONFIG_FILE")" -maxdepth 1 -type f \
    -name "$(basename -- "$CONFIG_FILE").tmux-status-observatory.*.bak" | wc -l)
[[ "$backup_count" -eq 1 ]]

setup_case dry_run
run_install --dry-run
[[ ! -e "$CONFIG_FILE" ]]
[[ ! -e "$CURL_LOG" ]]

printf 'install auto-location verification: PASS\n'
