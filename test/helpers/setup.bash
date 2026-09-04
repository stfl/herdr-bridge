# Shared bats setup: a hermetic PATH carrying stub `herdr` and `ssh`, a scratch
# XDG_RUNTIME_DIR, and a call log so tests can assert exactly what the script
# invoked and in what order.

HB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HB_BIN="$HB_ROOT/bin/herdr-bridge"
export HB_ROOT HB_BIN

hb_setup() {
  TEST_TMP="$(mktemp -d)"
  export TEST_TMP
  export XDG_RUNTIME_DIR="$TEST_TMP/run"
  export HB_CALLS="$TEST_TMP/calls.log"
  export HB_FIXTURES="$HB_ROOT/test/fixtures"
  export HB_STATE_DIR="$TEST_TMP/state"
  # Short and unique per test: the tool's own /tmp fallback is shared by every
  # run on the machine, which would leak forwards between tests.
  HERDR_BRIDGE_RUNTIME_DIR="$(mktemp -d /tmp/hb-XXXXXX)"
  export HERDR_BRIDGE_RUNTIME_DIR
  mkdir -p "$XDG_RUNTIME_DIR" "$HB_STATE_DIR"
  : >"$HB_CALLS"

  # Stub behaviour knobs, defaulted per test.
  export HB_SESSIONS=sessions.json
  export HB_AGENTS=agents-one.json
  export HB_AGENT_GET=agent-get.json
  export HB_ATTACH_MODE=exit0
  export HB_SSH_FAIL=0

  hb_install_stubs
  PATH="$TEST_TMP/bin:$PATH"
  export PATH
  export HOME="$TEST_TMP/home"
  mkdir -p "$HOME/.ssh"
}

hb_teardown() {
  [ -n "${TEST_TMP:-}" ] && rm -rf "$TEST_TMP"
  [ -n "${HERDR_BRIDGE_RUNTIME_DIR:-}" ] && rm -rf "$HERDR_BRIDGE_RUNTIME_DIR"
  return 0
}

hb_install_stubs() {
  mkdir -p "$TEST_TMP/bin"
  cp "$HB_ROOT/test/helpers/stub-herdr" "$TEST_TMP/bin/herdr"
  cp "$HB_ROOT/test/helpers/stub-ssh" "$TEST_TMP/bin/ssh"
  chmod +x "$TEST_TMP/bin/herdr" "$TEST_TMP/bin/ssh"
}

# Every `herdr ...` and `ssh ...` the script ran, one per line.
hb_calls() { cat "$HB_CALLS"; }

hb_calls_matching() { grep -F -- "$1" "$HB_CALLS" || true; }

hb_count_matching() { hb_calls_matching "$1" | grep -c . || true; }

# Source the script without running it, so pure functions can be tested
# directly. Fails loudly if the script executes its main flow on source.
hb_source() {
  # shellcheck disable=SC1090
  source "$HB_BIN"
}
