# Shared bats setup: a hermetic PATH carrying stub `herdr` and `ssh`, a scratch
# XDG_RUNTIME_DIR, and a call log so tests can assert exactly what the script
# invoked and in what order.

HB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HB_BIN="$HB_ROOT/bin/herdr-bridge"
export HB_ROOT HB_BIN

hb_setup() {
  # The suite is usually run from inside a herdr pane, which exports these.
  # Inheriting them makes a local run differ from CI, where they are absent —
  # HERDR_SOCKET_PATH in particular decides whether a `herdr` call is treated
  # as local or remote.
  unset HERDR_SOCKET_PATH HERDR_ENV HERDR_PANE_ID HERDR_TAB_ID \
    HERDR_WORKSPACE_ID HERDR_BIN_PATH HERDR_CONFIG_PATH

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
  export HB_SERVER_DOWN_FILE="$TEST_TMP/server-down"
  export HB_MUX_DIR="$TEST_TMP/mux"

  hb_install_stubs
  # The completions shell out to `herdr-bridge --complete`, so the tool has to
  # be reachable by name for them to be testable at all.
  ln -sf "$HB_BIN" "$TEST_TMP/bin/herdr-bridge"
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
