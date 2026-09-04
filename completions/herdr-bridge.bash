# bash completion for herdr-bridge
#
# Completes <host>:<session>:<remote-pane>. Candidates come from
# `herdr-bridge --complete`, which emits "value<TAB>description" lines.
#
# The candidate list holds whole values — "workbox:api", not "api". compgen
# matches the word being completed against the list it is given and applies
# -P only afterwards, so a prefix passed as -P can never make a fragment
# match. Building the list fully qualified is also what makes it testable
# without compgen, which some bash builds omit.
#
# ':' is in COMP_WORDBREAKS by default, so bash splits the target into several
# words. __ltrim_colon_completions (from bash-completion) trims the already
# typed prefix off the offered values; a local equivalent runs without it.
#
# Written for bash 3.2, which is still the system shell on macOS: no mapfile,
# no associative arrays.

_herdr_bridge_values() {
  herdr-bridge --complete "$@" 2>/dev/null | cut -f1
}

# Fully qualified candidates for a partially typed target.
_herdr_bridge_targets() {
  local cur="$1" host session value
  case "$cur" in
    *:*:*)
      host=${cur%%:*}
      session=${cur#*:}
      session=${session%%:*}
      _herdr_bridge_values agents "$host" "$session" | while IFS= read -r value; do
        [ -n "$value" ] && printf '%s:%s:%s\n' "$host" "$session" "$value"
      done
      ;;
    *:*)
      host=${cur%%:*}
      _herdr_bridge_values sessions "$host" | while IFS= read -r value; do
        [ -n "$value" ] && printf '%s:%s\n' "$host" "$value"
      done
      ;;
    *)
      _herdr_bridge_values hosts
      ;;
  esac
}

_herdr_bridge_ltrim() {
  if declare -F __ltrim_colon_completions >/dev/null 2>&1; then
    __ltrim_colon_completions "$1"
  else
    local prefix=${1%"${1##*:}"} i
    if [ -n "$prefix" ]; then
      for i in "${!COMPREPLY[@]}"; do
        COMPREPLY[i]=${COMPREPLY[i]#"$prefix"}
      done
    fi
  fi
}

_herdr_bridge() {
  local cur words cword word
  COMPREPLY=()

  if declare -F _get_comp_words_by_ref >/dev/null 2>&1; then
    _get_comp_words_by_ref -n : cur words cword
  else
    cur="${COMP_WORDS[COMP_CWORD]}"
    words=("${COMP_WORDS[@]}")
    cword=$COMP_CWORD
  fi

  case "${words[cword - 1]}" in
    --interval | --ttl) return 0 ;;
  esac

  if [ "${cur#-}" != "$cur" ]; then
    while IFS= read -r word; do
      [ -n "$word" ] && COMPREPLY[${#COMPREPLY[@]}]="$word"
    done < <(compgen -W "--list --release --takeover --interval --ttl \
      --version --help" -- "$cur")
    return 0
  fi

  while IFS= read -r word; do
    [ -n "$word" ] && COMPREPLY[${#COMPREPLY[@]}]="$word"
  done < <(compgen -W "$(_herdr_bridge_targets "$cur")" -- "$cur")

  _herdr_bridge_ltrim "$cur"
}

# Guarded: a bash built without programmable completion still has to be able
# to source this file, which is what makes the logic above testable.
complete -F _herdr_bridge herdr-bridge 2>/dev/null || true
