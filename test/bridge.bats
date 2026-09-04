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
  # Job control on, so the child gets its own process group and does not
  # inherit an ignored SIGINT the way a plain async child would. In a herdr
  # pane the tool runs in the foreground group, where ctrl-c behaves this way.
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
