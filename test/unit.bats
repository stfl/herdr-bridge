#!/usr/bin/env bats
# Pure-function tests. These source the script, so it must be sourceable
# without executing its main flow.

load helpers/setup

setup() { hb_setup; }
teardown() { hb_teardown; }

@test "the script can be sourced without running its main flow" {
  run bash -c 'source "$HB_BIN"; echo SOURCED_OK'
  [ "$status" -eq 0 ]
  [[ "$output" == *SOURCED_OK* ]]
  # Sourcing must not have made an SSH connection or touched herdr.
  [ "$(hb_count_matching 'ssh ')" -eq 0 ]
}

@test "parse_target splits host, session and pane" {
  run bash -c 'source "$HB_BIN"; parse_target workbox:api:w5:p1; echo "$TARGET_HOST|$TARGET_SESSION|$TARGET_PANE"'
  [ "$status" -eq 0 ]
  [ "$output" = "workbox|api|w5:p1" ]
}

@test "parse_target defaults the session to 'default'" {
  run bash -c 'source "$HB_BIN"; parse_target workbox; echo "$TARGET_HOST|$TARGET_SESSION|$TARGET_PANE"'
  [ "$status" -eq 0 ]
  [ "$output" = "workbox|default|" ]
}

@test "parse_target leaves the pane empty when only host and session are given" {
  run bash -c 'source "$HB_BIN"; parse_target workbox:api; echo "$TARGET_HOST|$TARGET_SESSION|$TARGET_PANE"'
  [ "$status" -eq 0 ]
  [ "$output" = "workbox|api|" ]
}

@test "parse_target rejects an empty host" {
  run bash -c 'source "$HB_BIN"; parse_target :api'
  [ "$status" -ne 0 ]
  [[ "$output" == *host* ]]
}

@test "parse_target rejects a trailing colon with no session" {
  run bash -c 'source "$HB_BIN"; parse_target workbox:'
  [ "$status" -ne 0 ]
  [[ "$output" == *session* ]]
}

@test "parse_target rejects an empty target" {
  run bash -c 'source "$HB_BIN"; parse_target ""'
  [ "$status" -ne 0 ]
}

@test "map_state passes through the four states herdr accepts" {
  run bash -c 'source "$HB_BIN"; for s in idle working blocked unknown; do printf "%s " "$(map_state $s)"; done'
  [ "$output" = "idle working blocked unknown " ]
}

@test "map_state folds 'done' onto idle" {
  run bash -c 'source "$HB_BIN"; map_state done'
  [ "$output" = "idle" ]
}

@test "map_state falls back to unknown for anything unrecognised" {
  run bash -c 'source "$HB_BIN"; map_state wat'
  [ "$output" = "unknown" ]
}

@test "client_socket derives herdr's client socket name" {
  run bash -c 'source "$HB_BIN"; client_socket /run/x/herdr.sock'
  [ "$output" = "/run/x/herdr-client.sock" ]
}

@test "local socket paths stay inside the sun_path limit" {
  run bash -c 'source "$HB_BIN"; local_socket workbox api'
  [ "$status" -eq 0 ]
  [ "${#output}" -lt 104 ]
}

@test "local socket paths for absurd names are rejected, not truncated" {
  long=$(printf 'x%.0s' $(seq 1 120))
  run bash -c "source \"\$HB_BIN\"; local_socket $long session"
  [ "$status" -ne 0 ]
}

@test "no bash 4-only builtins, so macOS's system bash can run it" {
  # macOS ships bash 3.2 as /bin/bash. mapfile/readarray and associative
  # arrays would abort the script there under `set -e`, and the failure looks
  # nothing like the cause.
  # Comment lines are stripped first: the reason these are avoided is written
  # down in the script, and naming them there must not trip the check.
  run bash -c "grep -vE '^[[:space:]]*#' \"\$HB_BIN\" |
    grep -nE '\\b(mapfile|readarray)\\b|declare -A'"
  [ "$status" -ne 0 ]
}

@test "a long XDG_RUNTIME_DIR falls back to a base that still fits" {
  # macOS puts the per-user temp directory under /var/folders/<...>, deep
  # enough that a socket beneath it exceeds sun_path.
  long="$TEST_TMP/$(printf 'deep/%.0s' $(seq 1 20))"
  mkdir -p "$long"
  run env -u HERDR_BRIDGE_RUNTIME_DIR XDG_RUNTIME_DIR="$long" \
    bash -c 'source "$HB_BIN"; local_socket workbox api'
  [ "$status" -eq 0 ]
  [ "${#output}" -lt 96 ]
}

@test "a symlinked runtime directory is refused rather than followed" {
  # Addressed directly, because a deep XDG_RUNTIME_DIR — which is what macOS
  # gives a test — would be traded for the short fallback and never looked at.
  local link="$TEST_TMP/rt-link"
  ln -s /tmp "$link"
  run env HERDR_BRIDGE_RUNTIME_DIR="$link" bash -c \
    'source "$HB_BIN"; ensure_runtime_dir'
  [ "$status" -ne 0 ]
  [[ "$output" == *"owned by this user"* ]]
}

@test "the bash completion parses" {
  run bash -n "$HB_ROOT/completions/herdr-bridge.bash"
  [ "$status" -eq 0 ]
}

@test "the zsh completion parses" {
  command -v zsh >/dev/null 2>&1 || skip "zsh not installed"
  run zsh -n "$HB_ROOT/completions/herdr-bridge.zsh"
  [ "$status" -eq 0 ]
}

@test "both completions delegate, rather than speaking herdr themselves" {
  # Candidates come only from `herdr-bridge --complete`, which the suite
  # covers directly. A completion that called herdr itself would be a second,
  # untested copy of the CLI knowledge, free to drift from the tool.
  local f
  for f in "$HB_ROOT/completions/herdr-bridge.zsh" \
    "$HB_ROOT/completions/herdr-bridge.bash"; do
    grep -q 'herdr-bridge --complete' "$f"
    run grep -nE '\bherdr (agent|pane|session|status|terminal) ' "$f"
    [ "$status" -ne 0 ]
  done
}
@test "a BSD date without %N still yields a numeric millisecond clock" {
  # macOS date has no %N conversion, so it survives into the output verbatim.
  # A non-numeric sequence number would break the arithmetic in teardown.
  # Shadowed as a shell function rather than on PATH, so only the script under
  # test sees it.
  run bash -c 'source "$HB_BIN"
    date() {
      case "$*" in
        *N*) printf "17884700003N\n" ;;
        *) printf "1788470000\n" ;;
      esac
    }
    now_ms'
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]+$ ]]
  [ "$output" = "1788470000000" ]
}

@test "the sequence clock never goes backwards" {
  run bash -c 'source "$HB_BIN"; a=$(now_ms); b=$(now_ms); [ "$b" -ge "$a" ]'
  [ "$status" -eq 0 ]
}

@test "flock is not required, because macOS does not ship it" {
  run bash -c 'source "$HB_BIN"; printf "%s\n" "${REQUIRED_TOOLS[@]}"'
  [ "$status" -eq 0 ]
  [[ "$output" != *flock* ]]
  [[ "$output" == *jq* ]]
}

@test "a second holder waits for the lock to be released" {
  run bash -c 'source "$HB_BIN"
    ensure_runtime_dir
    lock_acquire probe p
    ( lock_acquire probe p && echo SECOND_ENTERED ) &
    sleep 0.4
    echo FIRST_STILL_HOLDS
    lock_release probe p
    wait'
  [ "$status" -eq 0 ]
  [[ "$output" == *FIRST_STILL_HOLDS*SECOND_ENTERED* ]]
}

@test "a stale lock left by a dead process is broken, not waited on forever" {
  run bash -c 'source "$HB_BIN"
    ensure_runtime_dir
    mkdir -p "$(lock_path stale s)"
    echo 999999 >"$(lock_path stale s)/pid"
    LOCK_TIMEOUT=2 lock_acquire stale s && echo ACQUIRED
    lock_release stale s'
  [ "$status" -eq 0 ]
  [[ "$output" == *ACQUIRED* ]]
}

@test "a host name cannot escape the runtime directory" {
  # host and session reach path construction, and the lock is removed with
  # rm -rf, so traversal in either would be removal outside our own directory.
  run bash -c 'source "$HB_BIN"; local_socket "../../../tmp/pwn" "s"'
  [ "$status" -eq 0 ]
  [[ "$output" != *..* ]]
  [[ "$output" == "$HERDR_BRIDGE_RUNTIME_DIR/"* ]]
}

@test "a session name cannot escape the lock directory" {
  run bash -c 'source "$HB_BIN"; lock_path "h" "../../../tmp/pwn"'
  [ "$status" -eq 0 ]
  [[ "$output" != *..* ]]
  [[ "$output" == "$HERDR_BRIDGE_RUNTIME_DIR/"* ]]
}

@test "an ssh target with @ or : still yields a usable file name" {
  run bash -c 'source "$HB_BIN"; local_socket "user@host.example.com" "api"'
  [ "$status" -eq 0 ]
  [[ "$output" == "$HERDR_BRIDGE_RUNTIME_DIR/"*.sock ]]
  [[ "$(basename "$output")" != *@* ]]
}
