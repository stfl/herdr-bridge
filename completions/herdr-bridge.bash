# bash completion for herdr-bridge
#
# Completes <host>:<session>:<remote-pane> one colon-separated level at a
# time. Candidates come from `herdr-bridge --complete`, which emits
# "value<TAB>description" lines; bash shows values only.
#
# ':' is in COMP_WORDBREAKS by default, so bash splits the target into several
# words. __ltrim_colon_completions (from bash-completion) trims the already
# typed prefix off the offered values; without it, the shell would insert the
# prefix twice. A local equivalent runs when bash-completion is absent.

_herdr_bridge_values() {
  herdr-bridge --complete "$@" 2>/dev/null | cut -f1
}

_herdr_bridge_ltrim() {
  if declare -F __ltrim_colon_completions >/dev/null 2>&1; then
    __ltrim_colon_completions "$1"
  else
    local prefix=${1%"${1##*:}"}
    local i
    for i in "${!COMPREPLY[@]}"; do
      COMPREPLY[i]=${COMPREPLY[i]#"$prefix"}
    done
  fi
}

_herdr_bridge() {
  local cur words cword target host session
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

  if [[ $cur == -* ]]; then
    mapfile -t COMPREPLY < <(compgen -W \
      "--list --release --takeover --interval --ttl --version --help" -- "$cur")
    return 0
  fi

  target="$cur"
  case "$target" in
    *:*:*)
      host=${target%%:*}
      session=${target#*:}
      session=${session%%:*}
      mapfile -t COMPREPLY < <(compgen -W \
        "$(_herdr_bridge_values agents "$host" "$session")" -- "$target")
      ;;
    *:*)
      host=${target%%:*}
      mapfile -t COMPREPLY < <(compgen -P "$host:" -W \
        "$(_herdr_bridge_values sessions "$host")" -- "$target")
      ;;
    *)
      mapfile -t COMPREPLY < <(compgen -S : -W \
        "$(_herdr_bridge_values hosts)" -- "$target")
      compopt -o nospace 2>/dev/null
      ;;
  esac

  _herdr_bridge_ltrim "$cur"
}

complete -F _herdr_bridge herdr-bridge
