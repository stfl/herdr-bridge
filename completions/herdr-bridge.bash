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
      # Offered with the separator already attached, so one Tab moves to the
      # next level instead of stopping at a host name.
      _herdr_bridge_values hosts | while IFS= read -r value; do
        [ -n "$value" ] && printf '%s:\n' "$value"
      done
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

# Candidates are matched with a case glob rather than handed to `compgen -W`,
# which word-expands every entry in its list before matching. Session and pane
# names come from whatever the remote host reports, so a session called
# "$(...)" would otherwise run on this machine the moment Tab is pressed.
_herdr_bridge_filter() {
  local cur="$1" cand
  COMPREPLY=()
  while IFS= read -r cand; do
    [ -n "$cand" ] || continue
    case "$cand" in
      "$cur"*) COMPREPLY[${#COMPREPLY[@]}]="$cand" ;;
    esac
  done < <(_herdr_bridge_targets "$cur")
}

# Same matching for a list already in hand, such as the static options.
_herdr_bridge_filter_list() {
  local cur="$1" cand
  shift
  COMPREPLY=()
  for cand in "$@"; do
    case "$cand" in
      "$cur"*) COMPREPLY[${#COMPREPLY[@]}]="$cand" ;;
    esac
  done
}

# ':' is in COMP_WORDBREAKS, so by the time a completion function runs,
# readline has already split "workbox:api" into several words and COMP_WORDS
# cannot answer what is being completed. bash-completion's helper reassembles
# it; without that, the word is taken from the raw line, which is the only
# place it survives intact.
_herdr_bridge_current_word() {
  local cur line
  if declare -F _get_comp_words_by_ref >/dev/null 2>&1; then
    _get_comp_words_by_ref -n : cur
    printf '%s' "$cur"
    return 0
  fi
  if [ -n "${COMP_LINE:-}" ]; then
    line=${COMP_LINE:0:${COMP_POINT:-${#COMP_LINE}}}
    printf '%s' "${line##* }"
    return 0
  fi
  printf '%s' "${COMP_WORDS[COMP_CWORD]:-}"
}

_herdr_bridge() {
  local cur
  COMPREPLY=()

  case "${COMP_WORDS[COMP_CWORD - 1]:-}" in
    --interval | --ttl) return 0 ;;
  esac

  cur=$(_herdr_bridge_current_word)

  if [ "${cur#-}" != "$cur" ]; then
    _herdr_bridge_filter_list "$cur" \
      --list --release --takeover --interval --ttl --version --help
    return 0
  fi

  _herdr_bridge_filter "$cur"
  # Candidates that end in the separator are not finished words.
  case "${COMPREPLY[0]:-}" in
    *:) compopt -o nospace 2>/dev/null || true ;;
  esac
  _herdr_bridge_ltrim "$cur"
}

# Guarded: a bash built without programmable completion still has to be able
# to source this file, which is what makes the logic above testable.
complete -F _herdr_bridge herdr-bridge 2>/dev/null || true
