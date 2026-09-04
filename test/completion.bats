#!/usr/bin/env bats
# The bash completion's candidate construction. compgen only filters the list
# it is handed and applies -P afterwards, so the list must already hold whole
# values; that construction is the part worth pinning, and it needs no
# compgen, which some bash builds omit entirely.

load helpers/setup

setup() { hb_setup; }
teardown() { hb_teardown; }

targets() {
  bash -c "source '$HB_ROOT/completions/herdr-bridge.bash'
    _herdr_bridge_targets '$1'"
}

@test "the host level offers bare host names" {
  run env HERDR_BRIDGE_HOSTS="alpha beta" bash -c \
    "source '$HB_ROOT/completions/herdr-bridge.bash'; _herdr_bridge_targets ''"
  [ "$status" -eq 0 ]
  [[ "$output" == *alpha* ]]
}

@test "the session level offers host-qualified values, not bare sessions" {
  run targets "workbox:"
  [ "$status" -eq 0 ]
  [[ "$output" == *"workbox:api"* ]]
  # A bare "api" would never match the word being completed.
  [ "$(printf '%s\n' "$output" | grep -c '^workbox:')" -ge 2 ]
}

@test "a partially typed session still yields matchable candidates" {
  run targets "workbox:ap"
  [ "$status" -eq 0 ]
  [[ "$output" == *"workbox:api"* ]]
}

@test "the agent level offers fully qualified host:session:pane" {
  run targets "workbox:api:"
  [ "$status" -eq 0 ]
  [[ "$output" == *"workbox:api:w5:p1"* ]]
}

@test "a partially typed pane id still yields matchable candidates" {
  run targets "workbox:api:w5"
  [ "$status" -eq 0 ]
  [[ "$output" == *"workbox:api:w5:p1"* ]]
}

@test "the bash completion loads under a shell without programmable completion" {
  # `complete` is absent from some bash builds; sourcing must still succeed.
  run bash -c "source '$HB_ROOT/completions/herdr-bridge.bash' && echo LOADED"
  [ "$status" -eq 0 ]
  [[ "$output" == *LOADED* ]]
}

@test "the bash completion uses no bash 4-only builtins" {
  run bash -c "grep -vE '^[[:space:]]*#' '$HB_ROOT/completions/herdr-bridge.bash' |
    grep -nE '\\bmapfile\\b|\\breadarray\\b'"
  [ "$status" -ne 0 ]
}

@test "the zsh completion autoloads as a completion function" {
  command -v zsh >/dev/null 2>&1 || skip "zsh not installed"
  # `zsh -n` only parses. `autoload +X` loads the definition the way compinit
  # would, which is the first point at which a wrong function name or a
  # malformed body shows up.
  mkdir -p "$TEST_TMP/zfunc"
  cp "$HB_ROOT/completions/herdr-bridge.zsh" "$TEST_TMP/zfunc/_herdr-bridge"
  run zsh -f -c "
    fpath=('$TEST_TMP/zfunc' \$fpath)
    autoload -Uz compinit && compinit -u -d '$TEST_TMP/zcompdump' >/dev/null 2>&1
    autoload -Uz +X _herdr-bridge || exit 1
    (( \${+functions[_herdr-bridge]} )) || exit 1
    echo AUTOLOADED"
  [ "$status" -eq 0 ]
  [[ "$output" == *AUTOLOADED* ]]
}

@test "a remote session name cannot execute code during completion" {
  # compgen -W word-expands every entry in its list before matching, and
  # session names are whatever the remote host reports. Pressing Tab must not
  # run them.
  export HB_SESSIONS=sessions-hostile.json
  export HB_INJECT_MARKER="$TEST_TMP/injected"
  run bash -c "source '$HB_ROOT/completions/herdr-bridge.bash'
    _herdr_bridge_filter 'workbox:'
    printf '%s\n' \"\${COMPREPLY[@]}\""
  [ "$status" -eq 0 ]
  # The payload's side effect, not its text: the name itself legitimately
  # contains the words it would print.
  [ ! -e "$HB_INJECT_MARKER" ]
  [ ! -e "$HB_INJECT_MARKER.bt" ]
  # And it is still offered, as inert text.
  [[ "$output" == *'$(touch'* ]]
}

@test "candidates are still offered when a name contains shell syntax" {
  export HB_SESSIONS=sessions-hostile.json
  run bash -c "source '$HB_ROOT/completions/herdr-bridge.bash'
    _herdr_bridge_filter 'workbox:'
    printf '%s\n' \"\${COMPREPLY[@]}\""
  [[ "$output" == *"workbox:default"* ]]
}

@test "the filter keeps only candidates matching what was typed" {
  run bash -c "source '$HB_ROOT/completions/herdr-bridge.bash'
    _herdr_bridge_filter 'workbox:ap'
    printf '%s\n' \"\${COMPREPLY[@]}\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"workbox:api"* ]]
  [[ "$output" != *"workbox:default"* ]]
}

@test "the fallback path completes below the host level" {
  # Without bash-completion's helpers, readline has already split the target
  # at ':' and COMP_WORDS cannot say what is being completed; the word has to
  # come from the raw line, which is the only place it survives whole.
  run bash -c "source '$HB_ROOT/completions/herdr-bridge.bash'
    COMP_LINE='herdr-bridge workbox:ap'
    COMP_POINT=\${#COMP_LINE}
    COMP_WORDS=(herdr-bridge workbox : ap)
    COMP_CWORD=3
    _herdr_bridge
    printf '%s\n' \"\${COMPREPLY[@]}\""
  [ "$status" -eq 0 ]
  [ "$output" = "api" ]
}

@test "the fallback path completes a pane id below the session level" {
  run bash -c "source '$HB_ROOT/completions/herdr-bridge.bash'
    COMP_LINE='herdr-bridge workbox:api:w5'
    COMP_POINT=\${#COMP_LINE}
    COMP_WORDS=(herdr-bridge workbox : api : w5)
    COMP_CWORD=5
    _herdr_bridge
    printf '%s\n' \"\${COMPREPLY[@]}\""
  [ "$status" -eq 0 ]
  [ "$output" = "w5:p1" ]
}

@test "the host level offers the separator so one Tab moves on" {
  run bash -c "source '$HB_ROOT/completions/herdr-bridge.bash'
    HERDR_BRIDGE_HOSTS='alpha beta' _herdr_bridge_targets ''"
  [ "$status" -eq 0 ]
  [[ "$output" == *"alpha:"* ]]
}

@test "options are still offered, and are not remote data" {
  run bash -c "source '$HB_ROOT/completions/herdr-bridge.bash'
    _herdr_bridge_filter_list '--re' --list --release --takeover
    printf '%s\n' \"\${COMPREPLY[@]}\""
  [ "$output" = "--release" ]
}
