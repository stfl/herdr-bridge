#!/usr/bin/env bats
# Completion data. The zsh function is a thin shell over these, so the
# contract that matters is the "value<TAB>description" stream.

load helpers/setup

setup() { hb_setup; }
teardown() { hb_teardown; }

@test "hosts come from HERDR_BRIDGE_HOSTS" {
  # Names that cannot collide with the machine running the suite, which is
  # deliberately filtered out of the results.
  HERDR_BRIDGE_HOSTS="alpha beta" run "$HB_BIN" --complete hosts
  [ "$status" -eq 0 ]
  [[ "$output" == *"alpha"$'\t'"herdr host"* ]]
  [[ "$output" == *"beta"$'\t'"herdr host"* ]]
}

@test "hosts also come from ssh config, without wildcard stanzas" {
  cat >"$HOME/.ssh/config" <<EOF
Host workbox
  HostName example.com
Host *.internal
  User u
Host a b
  User u
EOF
  run "$HB_BIN" --complete hosts
  [ "$status" -eq 0 ]
  [[ "$output" == *"workbox"$'\t'"ssh config"* ]]
  [[ "$output" == *$'a\tssh config'* ]]
  [[ "$output" == *$'b\tssh config'* ]]
  [[ "$output" != *"*.internal"* ]]
}

@test "a host listed in both places appears once, env description winning" {
  printf 'Host workbox\n  HostName k\n' >"$HOME/.ssh/config"
  HERDR_BRIDGE_HOSTS="workbox" run "$HB_BIN" --complete hosts
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c '^workbox')" -eq 1 ]
  [[ "$output" == *"workbox"$'\t'"herdr host"* ]]
}

@test "the local machine is not offered as a bridge target" {
  HERDR_BRIDGE_HOSTS="$(uname -n) workbox" run "$HB_BIN" --complete hosts
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c "^$(uname -n)\b")" -eq 0 ]
}

@test "sessions are listed with running state, default marked" {
  run "$HB_BIN" --complete sessions workbox
  [ "$status" -eq 0 ]
  [[ "$output" == *"default"$'\t'"running · default"* ]]
  [[ "$output" == *"api"$'\t'"running"* ]]
}

@test "stopped sessions are not offered" {
  run "$HB_BIN" --complete sessions workbox
  [[ "$output" != *stopped* ]]
}

@test "agents keep their colon-bearing pane id in the value field" {
  run "$HB_BIN" --complete agents workbox api
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | cut -f1)" = "w5:p1" ]
  [[ "$(printf '%s\n' "$output" | cut -f2)" == "claude · done · auth middleware" ]]
}

@test "completion never prompts: ssh runs in batch mode" {
  run "$HB_BIN" --complete sessions workbox
  [ -n "$(hb_calls_matching 'BatchMode=yes')" ]
}

@test "completion fails quietly when the host is unreachable" {
  HB_SSH_FAIL=1 run "$HB_BIN" --complete sessions workbox
  [ -z "$output" ]
}

@test "an unknown completion topic is refused" {
  run "$HB_BIN" --complete wat
  [ "$status" -ne 0 ]
}
