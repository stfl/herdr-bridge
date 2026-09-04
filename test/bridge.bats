#!/usr/bin/env bats
# The behaviour the tool exists for: a remote agent published onto a local
# pane, and reliably withdrawn again.

load helpers/setup

setup() {
  hb_setup
  export HERDR_PANE_ID=w1:p2
}
teardown() { hb_teardown; }

# Wait until the call log matches, or fail after `timeout` tenths of a second.
hb_wait_for() {
  local needle="$1" tries="${2:-100}"
  while [ "$tries" -gt 0 ]; do
    if grep -qF -- "$needle" "$HB_CALLS"; then return 0; fi
    tries=$((tries - 1))
    sleep 0.1
  done
  return 1
}

@test "the remote agent is published onto the local pane" {
  run "$HB_BIN" workbox:api:w5:p1
  [ "$status" -eq 0 ]
  [ -n "$(hb_calls_matching 'pane report-agent w1:p2')" ]
}

@test "herdr's 'done' is published as idle, which report-agent accepts" {
  run "$HB_BIN" workbox:api:w5:p1
  [ -n "$(hb_calls_matching '--state idle')" ]
  [ -z "$(hb_calls_matching '--state done')" ]
}

@test "the row is tagged with the host it really runs on" {
  run "$HB_BIN" workbox:api:w5:p1
  [ -n "$(hb_calls_matching '--display-agent claude@workbox')" ]
  [ -n "$(hb_calls_matching '--token host=workbox')" ]
  [ -n "$(hb_calls_matching '--token session=api')" ]
}

@test "the remote agent's session id travels with the row" {
  run "$HB_BIN" workbox:api:w5:p1
  [ -n "$(hb_calls_matching '--agent-session-id 2577af67-6b47-4f89-96bb-412204864866')" ]
}

@test "metadata carries a ttl so a vanished bridge decays" {
  run "$HB_BIN" --ttl 4000 workbox:api:w5:p1
  [ -n "$(hb_calls_matching '--ttl-ms 4000')" ]
}

@test "the row is released when the attach ends" {
  run "$HB_BIN" workbox:api:w5:p1
  [ "$status" -eq 0 ]
  [ -n "$(hb_calls_matching 'pane release-agent w1:p2')" ]
}

@test "the release outranks every report, so a late one cannot resurrect it" {
  run "$HB_BIN" workbox:api:w5:p1
  local last_report release
  last_report=$(hb_calls_matching 'pane report-agent' | tail -1 |
    sed 's/.*--seq \([0-9]*\).*/\1/')
  release=$(hb_calls_matching 'pane release-agent' | tail -1 |
    sed 's/.*--seq \([0-9]*\).*/\1/')
  [ -n "$last_report" ]
  [ -n "$release" ]
  [ "$release" -gt "$last_report" ]
  # And only just. A large margin would black out re-bridging the same pane
  # for its duration, because a fresh run publishes with the wall clock and
  # would rank below the release it is trying to supersede.
  [ "$((release - last_report))" -lt 10000 ]
}

@test "a session with several agents refuses instead of guessing" {
  HB_AGENTS=agents-two.json run "$HB_BIN" workbox:default
  [ "$status" -ne 0 ]
  [[ "$output" == *"w6:pC"* ]]
  [[ "$output" == *"w6:pD"* ]]
  [ -z "$(hb_calls_matching 'pane report-agent')" ]
}

@test "a lone agent is selected without being named" {
  run "$HB_BIN" workbox:api
  [ "$status" -eq 0 ]
  [ -n "$(hb_calls_matching 'agent attach w5:p1')" ]
}

@test "--takeover reaches the attach" {
  run "$HB_BIN" --takeover workbox:api:w5:p1
  [ -n "$(hb_calls_matching 'agent attach w5:p1 --takeover')" ]
}

@test "SIGTERM during a live attach releases the row promptly" {
  HB_ATTACH_MODE=hang "$HB_BIN" workbox:api:w5:p1 >/dev/null 2>&1 &
  local pid=$!
  hb_wait_for 'pane report-agent w1:p2' || {
    kill "$pid" 2>/dev/null
    false
  }
  kill -TERM "$pid"
  # Two seconds is generous; the real teardown is a few hundred ms.
  run hb_wait_for 'pane release-agent w1:p2' 20
  [ "$status" -eq 0 ]
  wait "$pid" 2>/dev/null || true
}

@test "SIGINT during a live attach releases the row too" {
  # A delivered SIGINT, not a keystroke: the attach holds the terminal in raw
  # mode, so ctrl-c goes to the remote agent. This covers `kill -INT` and any
  # other route by which a signal actually arrives.
  # Job control on, so the child gets its own process group and does not
  # inherit an ignored SIGINT the way a plain async child would.
  set -m
  HB_ATTACH_MODE=hang "$HB_BIN" workbox:api:w5:p1 >/dev/null 2>&1 &
  local pid=$!
  set +m
  hb_wait_for 'pane report-agent w1:p2' || {
    kill "$pid" 2>/dev/null
    false
  }
  kill -INT "$pid"
  run hb_wait_for 'pane release-agent w1:p2' 20
  [ "$status" -eq 0 ]
  wait "$pid" 2>/dev/null || true
}

@test "an already-live forward is reused rather than rebuilt" {
  run "$HB_BIN" --list workbox:api
  local first
  first=$(hb_count_matching '-L ')
  [ "$first" -ge 1 ]
  run "$HB_BIN" --list workbox:api
  [ "$(hb_count_matching '-L ')" -eq "$first" ]
}

@test "a dead socket is detected despite herdr's zero exit status" {
  # The stub reproduces `status server` exiting 0 while reporting a dead
  # socket; if that fooled the check, no forward would ever be built.
  run "$HB_BIN" --list workbox:api
  [ -n "$(hb_calls_matching '-L ')" ]
}

@test "a socket file with nothing listening rebuilds the forward" {
  # The trap herdr sets: `status server` exits 0 while reporting a dead
  # socket. A liveness check on the file's existence, or on that exit code,
  # would reuse a forward that leads nowhere.
  mkdir -p "$HERDR_BRIDGE_RUNTIME_DIR"
  python3 -c 'import socket,sys
s = socket.socket(socket.AF_UNIX)
s.bind(sys.argv[1])' "$HERDR_BRIDGE_RUNTIME_DIR/$(bash -c 'source "$HB_BIN"; path_key workbox api').sock"
  export HB_SERVER_DOWN=1
  run "$HB_BIN" --list workbox:api
  [ -n "$(hb_calls_matching '-L ')" ]
}

@test "the mirror keeps republishing while the attach lives" {
  cp "$HB_FIXTURES/agent-get.json" "$TEST_TMP/agent.json"
  HB_AGENT_GET_FILE="$TEST_TMP/agent.json" HB_ATTACH_MODE=hang \
    "$HB_BIN" --interval 0.2 workbox:api:w5:p1 >/dev/null 2>&1 &
  local pid=$!
  hb_wait_for 'pane report-agent w1:p2' || { kill "$pid" 2>/dev/null; false; }
  # More than the single publish made before the attach starts.
  local tries=40
  while [ "$(hb_count_matching 'pane report-agent w1:p2')" -lt 3 ] &&
    [ "$tries" -gt 0 ]; do
    tries=$((tries - 1))
    sleep 0.1
  done
  kill -TERM "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null || true
  [ "$(hb_count_matching 'pane report-agent w1:p2')" -ge 3 ]
}

@test "the mirror picks up a state change on the remote agent" {
  cp "$HB_FIXTURES/agent-get.json" "$TEST_TMP/agent.json"
  HB_AGENT_GET_FILE="$TEST_TMP/agent.json" HB_ATTACH_MODE=hang \
    "$HB_BIN" --interval 0.2 workbox:api:w5:p1 >/dev/null 2>&1 &
  local pid=$!
  hb_wait_for '--state idle' || { kill "$pid" 2>/dev/null; false; }
  sed -i 's/"agent_status":"done"/"agent_status":"blocked"/' "$TEST_TMP/agent.json"
  run hb_wait_for '--state blocked' 40
  kill -TERM "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null || true
  [ "$status" -eq 0 ]
}

@test "a pane id with no agent behind it is refused" {
  run "$HB_BIN" workbox:api:w9:p9
  [ "$status" -ne 0 ]
  [ -z "$(hb_calls_matching 'pane report-agent')" ]
}

@test "--release clears a bridged row using the tokens it carries" {
  export HB_LOCAL_ROW="$HB_FIXTURES/local-bridged-row.json"
  run "$HB_BIN" --release
  [ "$status" -eq 0 ]
  [ -n "$(hb_calls_matching 'pane release-agent w1:p2 --source herdr-bridge:workbox:api --agent claude')" ]
}

@test "--release refuses a pane that carries no bridged agent" {
  export HB_LOCAL_ROW="$HB_FIXTURES/local-plain-row.json"
  run "$HB_BIN" --release
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not carry a bridged agent"* ]]
  [ -z "$(hb_calls_matching 'pane release-agent')" ]
}

@test "--release outside a herdr pane refuses" {
  unset HERDR_PANE_ID
  run "$HB_BIN" --release
  [ "$status" -ne 0 ]
  [[ "$output" == *"not inside a herdr pane"* ]]
}
