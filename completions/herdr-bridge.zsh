#compdef herdr-bridge

# Completes <host>:<session>:<remote-pane> one colon-separated level at a
# time. Candidates come from `herdr-bridge --complete`, so this file knows
# nothing about herdr's own CLI: the session level reaches the host over the
# shared SSH connection, the agent level over the forwarded socket. Each
# candidate line is "value<TAB>description" — tab, because a remote pane id
# (w5:p1) carries a colon of its own.

_herdr_bridge_candidates() {
  # _herdr_bridge_candidates <tag> <label> <suffix> <complete-args...>
  local tag=$1 label=$2 suffix=$3
  shift 3

  local -a vals descs lines opts
  local line
  lines=( ${(f)"$(herdr-bridge --complete "$@" 2>/dev/null)"} )

  for line in $lines; do
    [[ -n $line ]] || continue
    vals+=( ${line%%$'\t'*} )
    if [[ $line == *$'\t'* ]]; then
      descs+=( "${line%%$'\t'*} -- ${line#*$'\t'}" )
    else
      descs+=( ${line} )
    fi
  done
  (( $#vals )) || return 1

  opts=( -Q -d descs )
  [[ -n $suffix ]] && opts+=( -S $suffix )

  local expl
  _wanted $tag expl $label compadd $opts -a vals
}

_herdr_bridge_target() {
  local -a match mbegin mend

  # Deepest level first: the pane id keeps its own colon, so it consumes the
  # remainder of the word.
  if compset -P '(#b)([^:]##):([^:]##):'; then
    _herdr_bridge_candidates agents 'remote agent' '' \
      agents $match[1] $match[2]
    return
  fi

  if compset -P '(#b)([^:]##):'; then
    _herdr_bridge_candidates sessions 'herdr session' ':' \
      sessions $match[1]
    return
  fi

  _herdr_bridge_candidates hosts 'host' ':' hosts
}

_herdr-bridge() {
  _arguments -s -S \
    '(-h --help)'{-h,--help}'[show usage]' \
    '(-V --version)'{-V,--version}'[print version]' \
    '--list[list sessions on a host, or agents in a session]' \
    '--release[clear a mirrored row stuck on this pane]' \
    '--takeover[take input ownership from an existing client]' \
    '--interval[seconds between state polls]:seconds:' \
    '--ttl[ms before a mirrored sidebar row expires]:milliseconds:' \
    '1:target:_herdr_bridge_target'
}

_herdr-bridge "$@"
