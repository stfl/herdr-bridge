#!/usr/bin/env bats
# --list, against stub ssh and herdr.

load helpers/setup

setup() { hb_setup; }
teardown() { hb_teardown; }

@test "--list <host> asks the host for its sessions" {
  run "$HB_BIN" --list workbox
  [ "$status" -eq 0 ]
  [ -n "$(hb_calls_matching 'herdr session list')" ]
}

@test "--list <host:session> forwards both sockets" {
  run "$HB_BIN" --list workbox:api
  [ "$status" -eq 0 ]
  # Both halves of herdr's socket pair, with its own naming preserved.
  [ -n "$(hb_calls_matching 'workbox-api.sock:/home/u/.config/herdr/sessions/api/herdr.sock')" ]
  [ -n "$(hb_calls_matching 'workbox-api-client.sock:/home/u/.config/herdr/sessions/api/herdr-client.sock')" ]
}

@test "--list <host:session> prints a table of agents" {
  run "$HB_BIN" --list workbox:api
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == PANE*AGENT*STATE*TITLE* ]]
  [[ "$output" == *"w5:p1"* ]]
  [[ "$output" == *claude* ]]
}

@test "an unknown session is refused with a pointer to --list" {
  run "$HB_BIN" --list workbox:nosuch
  [ "$status" -ne 0 ]
  [[ "$output" == *"no running session"* ]]
}

@test "a stopped session is refused rather than silently forwarded" {
  run "$HB_BIN" --list workbox:stopped
  [ "$status" -ne 0 ]
  [[ "$output" == *"no running session"* ]]
  [ -z "$(hb_calls_matching '-L ')" ]
}

@test "--list refuses a pane-level target" {
  run "$HB_BIN" --list workbox:api:w5:p1
  [ "$status" -ne 0 ]
  [[ "$output" == *pane* ]]
}

@test "an ssh failure is reported, not swallowed" {
  HB_SSH_FAIL=1 run "$HB_BIN" --list workbox
  [ "$status" -ne 0 ]
}

@test "ssh is invoked with connection multiplexing options" {
  # Guards against the options array silently coming out empty, which is what
  # a bash-4-only builtin would do on an older shell.
  run "$HB_BIN" --list workbox
  [ "$status" -eq 0 ]
  [ -n "$(hb_calls_matching 'ControlMaster=auto')" ]
  [ -n "$(hb_calls_matching 'ControlPersist')" ]
}
