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

@test "a leftover file at the lock path does not block forever" {
  # An earlier implementation held the lock as a file. mkdir can never
  # succeed against one, and it carries no pid to judge staleness by, so it
  # would wedge every later run.
  run bash -c 'source "$HB_BIN"
    ensure_runtime_dir
    : >"$(lock_path h s)"
    LOCK_TIMEOUT=3 lock_acquire h s && echo ACQUIRED
    lock_release h s'
  [ "$status" -eq 0 ]
  [[ "$output" == *ACQUIRED* ]]
}

@test "a lock directory with no owner recorded is reclaimed" {
  # A holder killed between mkdir and writing its pid leaves exactly this.
  run bash -c 'source "$HB_BIN"
    ensure_runtime_dir
    mkdir -p "$(lock_path h s)"
    LOCK_TIMEOUT=5 lock_acquire h s && echo ACQUIRED
    lock_release h s'
  [ "$status" -eq 0 ]
  [[ "$output" == *ACQUIRED* ]]
}

@test "path keys do not collide across different host/session splits" {
  # '-' is both a legal character and the obvious joiner, so sanitising alone
  # would give dev-box/api and dev/box-api the same socket and lock, and the
  # second bridge would silently drive the first one's server.
  # Exercised through the real entry points, because the collision is in how
  # they build the key, not in the sanitiser alone.
  run bash -c 'source "$HB_BIN"
    a=$(local_socket "dev-box" "api");  b=$(local_socket "dev" "box-api")
    c=$(lock_path   "dev-box" "api");  d=$(lock_path   "dev" "box-api")
    [ "$a" != "$b" ] && [ "$c" != "$d" ] && echo DISTINCT'
  [ "$status" -eq 0 ]
  [[ "$output" == *DISTINCT* ]]
}

@test "path keys do not collide after character substitution" {
  # Two different ssh targets must not share a ControlPath either.
  run bash -c 'source "$HB_BIN"
    ssh_opts "user@host"; a="${SSH_OPTS[*]}"
    ssh_opts "user_host"; b="${SSH_OPTS[*]}"
    [ "$a" != "$b" ] && echo DISTINCT'
  [ "$status" -eq 0 ]
  [[ "$output" == *DISTINCT* ]]
}

@test "socket paths still fit once the key carries a checksum" {
  run bash -c 'source "$HB_BIN"; local_socket "some-longish-host.example.com" "session"'
  [ "$status" -eq 0 ]
  [ "${#output}" -lt 96 ]
}

@test "is_positive_number rejects a second decimal point" {
  run bash -c 'source "$HB_BIN"; is_positive_number "1.2.3"'
  [ "$status" -ne 0 ]
}

@test "--ttl requires whole milliseconds" {
  run "$HB_BIN" --ttl 1.5 workbox:api
  [ "$status" -ne 0 ]
  [[ "$output" == *"--ttl"* ]]
}

@test "ssh is given keepalives and a connect timeout" {
  # Without them a suspended laptop leaves calls hanging on a dead master
  # while the forward lock is held, which takes sibling panes down with it.
  run bash -c 'source "$HB_BIN"; ssh_opts host; printf "%s\n" "${SSH_OPTS[@]}"'
  [ "$status" -eq 0 ]
  [[ "$output" == *ServerAliveInterval* ]]
  [[ "$output" == *ServerAliveCountMax* ]]
  [[ "$output" == *ConnectTimeout* ]]
}

@test "contending processes never hold a reclaimed stale lock at once" {
  # Mutual exclusion checked directly with a sentinel, rather than by reading
  # the order of log lines, which depends on how the runner schedules them.
  run bash -c 'source "$HB_BIN"
    ensure_runtime_dir
    mkdir -p "$(lock_path h s)"
    echo 999999 >"$(lock_path h s)/pid"
    held="$HERDR_BRIDGE_RUNTIME_DIR/held"
    log="$HERDR_BRIDGE_RUNTIME_DIR/log"
    : >"$log"
    for _ in 1 2 3 4; do
      (
        LOCK_TIMEOUT=30 lock_acquire h s
        if [ -e "$held" ]; then echo OVERLAP >>"$log"; fi
        : >"$held"
        sleep 0.05
        rm -f "$held"
        echo DONE >>"$log"
        lock_release h s
      ) &
    done
    wait
    printf "overlaps=%s done=%s\n" \
      "$(grep -c OVERLAP "$log" || true)" "$(grep -c DONE "$log" || true)"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"overlaps=0"* ]]
  # Every contender got the lock, so none timed out waiting on the stale one.
  [[ "$output" == *"done=4"* ]]
}

# Replays an entry/exit log and prints the greatest number of holders that
# were ever inside at once. Anything above 1 is a double-hold.
hb_max_concurrent() {
  awk '$1 == "+" { n++; if (n > m) m = n; next } { n-- } END { print m + 0 }' "$1"
}

@test "a stale lock never admits two holders, over repeated contention" {
  export HB_BIN
  export HB_LOG="$HERDR_BRIDGE_RUNTIME_DIR/log"
  export HB_READY="$HERDR_BRIDGE_RUNTIME_DIR/ready"
  : >"$HB_LOG"
  bash -c 'source "$HB_BIN"; ensure_runtime_dir'

  local round i pid
  for round in $(seq 1 "${HB_RACE_ROUNDS:-5}"); do
    rm -f "$HB_READY"
    "$HB_ROOT/test/helpers/lock-victim" &
    pid=$!
    for i in $(seq 1 200); do
      [ -e "$HB_READY" ] && break
      sleep 0.01
    done
    kill -9 "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    for i in $(seq 1 "${HB_RACE_WAITERS:-8}"); do
      "$HB_ROOT/test/helpers/lock-waiter" &
    done
    wait
  done

  local max
  max=$(hb_max_concurrent "$HB_LOG")
  echo "max_concurrent=$max"
  [ "$max" -eq 1 ]
}

@test "a staggered staleness verdict cannot rename a live lock away" {
  # Deterministic: contender 1 reclaims and re-creates the lock, contender 2
  # is still holding the verdict it formed beforehand. A verdict re-read under
  # the reclaim guard is unaffected by any delay.
  export HB_BIN HB_HOLD=0.5
  export HB_LOG="$HERDR_BRIDGE_RUNTIME_DIR/log"
  : >"$HB_LOG"
  bash -c 'source "$HB_BIN"; ensure_runtime_dir'

  export HB_READY="$HERDR_BRIDGE_RUNTIME_DIR/ready"
  local i pid
  rm -f "$HB_READY"
  "$HB_ROOT/test/helpers/lock-victim" &
  pid=$!
  for i in $(seq 1 200); do
    [ -e "$HB_READY" ] && break
    sleep 0.01
  done
  kill -9 "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true

  for i in 1 2 3; do
    HB_DELAY=$(awk -v i="$i" 'BEGIN { printf "%.1f", (i - 1) * 0.1 }') \
      "$HB_ROOT/test/helpers/lock-waiter" &
  done
  wait

  local max
  max=$(hb_max_concurrent "$HB_LOG")
  echo "max_concurrent=$max"
  [ "$max" -eq 1 ]
}

@test "a process is only called dead on an unambiguous answer" {
  # A false "dead" is the only verdict that can hand one lock to two holders,
  # and ps can fail to run at all under the fork pressure of several panes
  # starting at once. That must read as alive.
  run bash -c 'source "$HB_BIN"
    kill() { return 1; }
    ps() { return 127; }
    if pid_alive 4000000; then echo ALIVE; else echo DEAD; fi'
  [ "$status" -eq 0 ]
  [ "$output" = ALIVE ]
}

@test "a process ps reports as absent is called dead" {
  run bash -c 'source "$HB_BIN"
    kill() { return 1; }
    ps() { return 1; }
    if pid_alive 4000000; then echo ALIVE; else echo DEAD; fi'
  [ "$output" = DEAD ]
}

@test "a live process is called alive even when kill cannot signal it" {
  # kill -0 reports EPERM for a pid owned by another user.
  run bash -c 'source "$HB_BIN"
    kill() { return 1; }
    ps() { return 0; }
    if pid_alive 1; then echo ALIVE; else echo DEAD; fi'
  [ "$output" = ALIVE ]
}

@test "a guard left behind by a dead reclaimer is broken promptly" {
  # Judged by the reclaimer's pid, not only by age: find's minute granularity
  # would otherwise stall every waiter well past LOCK_TIMEOUT.
  run bash -c 'source "$HB_BIN"
    ensure_runtime_dir
    lock="$(lock_path h s)"
    mkdir -p "$lock.reclaim"
    printf 4000000 >"$lock.reclaim/pid"
    printf 4000000 >"$lock"
    LOCK_TIMEOUT=5 lock_acquire h s && echo ACQUIRED
    lock_release h s'
  [ "$status" -eq 0 ]
  [[ "$output" == *ACQUIRED* ]]
}

@test "reclaiming a stale lock leaves nothing behind" {
  # The guard holds its owner's pid, so removing it with rmdir fails and the
  # guard survives — after which no later reclaim can take it and every
  # waiter times out instead.
  run bash -c 'source "$HB_BIN"
    ensure_runtime_dir
    printf 4000000 >"$(lock_path h s)"
    LOCK_TIMEOUT=5 lock_acquire h s
    lock_release h s
    ls -A "$HERDR_BRIDGE_RUNTIME_DIR"'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "two reclaims in a row both succeed" {
  run bash -c 'source "$HB_BIN"
    ensure_runtime_dir
    for _ in 1 2; do
      printf 4000000 >"$(lock_path h s)"
      LOCK_TIMEOUT=5 lock_acquire h s
      lock_release h s
    done
    echo BOTH'
  [ "$status" -eq 0 ]
  [[ "$output" == *BOTH* ]]
}

@test "ps is required, because liveness cannot be judged without it" {
  # Liveness fails closed, so a missing ps means no stale lock is ever
  # reclaimed and every waiter times out. Better to say so up front.
  run bash -c 'source "$HB_BIN"; printf "%s\n" "${REQUIRED_TOOLS[@]}"'
  [ "$status" -eq 0 ]
  [[ "$output" == *ps* ]]
}
