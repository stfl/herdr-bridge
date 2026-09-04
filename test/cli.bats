#!/usr/bin/env bats
# Argument handling and refusals that must not need a network.

load helpers/setup

setup() { hb_setup; }
teardown() { hb_teardown; }

@test "--help explains the target grammar and exits 0" {
  run "$HB_BIN" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"<host>[:<session>[:<remote-pane>]]"* ]]
}

@test "--version reports the version" {
  run "$HB_BIN" --version
  [ "$status" -eq 0 ]
  [[ "$output" == "herdr-bridge "* ]]
}

@test "an unknown option is refused rather than treated as a target" {
  run "$HB_BIN" --wat workbox
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown option"* ]]
}

@test "--interval rejects a non-numeric value" {
  run "$HB_BIN" --interval abc workbox
  [ "$status" -ne 0 ]
  [[ "$output" == *"--interval"* ]]
}

@test "--interval rejects zero" {
  run "$HB_BIN" --interval 0 workbox
  [ "$status" -ne 0 ]
}

@test "--ttl rejects a negative value" {
  run "$HB_BIN" --ttl -5 workbox
  [ "$status" -ne 0 ]
}

@test "--interval accepts a fractional value" {
  HERDR_PANE_ID=w1:p1 run "$HB_BIN" --interval 0.5 workbox:api:w5:p1
  [ "$status" -eq 0 ]
}

@test "attaching outside a herdr pane refuses with a usable message" {
  unset HERDR_PANE_ID
  run "$HB_BIN" workbox:api
  [ "$status" -ne 0 ]
  [[ "$output" == *"not inside a herdr pane"* ]]
}

@test "no target at all prints usage and fails" {
  HERDR_PANE_ID=w1:p1 run "$HB_BIN"
  [ "$status" -ne 0 ]
  [[ "$output" == *usage* ]]
}

@test "a missing tool is reported by name" {
  # Hide one tool from the lookup rather than rebuilding PATH, which would
  # also have to keep the shell itself reachable.
  run bash -c 'source "$HB_BIN"
    command() {
      if [ "${1-}" = -v ] && [ "${2-}" = jq ]; then return 1; fi
      builtin command "$@"
    }
    require_tools'
  [ "$status" -ne 0 ]
  [[ "$output" == *"jq is not on PATH"* ]]
}

@test "every option shown in --help is accepted by the parser" {
  # A flag can be documented, implemented and dispatched and still be
  # rejected, because the parser has no case for it. That is exactly how
  # --disconnect shipped broken in 0.0.2.
  local opt rejected=""
  for opt in $("$HB_BIN" --help | sed -n 's/^  \(--[a-z-]*\).*/\1/p' | sort -u); do
    run "$HB_BIN" "$opt"
    if [[ "$output" == *"unknown option"* ]]; then
      rejected="$rejected $opt"
    fi
  done
  [ -z "$rejected" ] || {
    echo "documented but rejected:$rejected"
    false
  }
}

@test "--disconnect without a host explains itself" {
  run "$HB_BIN" --disconnect
  [ "$status" -ne 0 ]
  [[ "$output" == *"--disconnect <host>"* ]]
}

@test "--disconnect closes the shared connection" {
  run "$HB_BIN" --disconnect workbox
  [ "$status" -eq 0 ]
  [ -n "$(hb_calls_matching '-O exit')" ]
  [[ "$output" == *"closed the shared connection"* ]]
}
