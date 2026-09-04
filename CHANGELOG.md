# Changelog

## 0.0.2

Fixes from an adversarial review of 0.0.1.

- Bash completion offered nothing below the host level: `compgen -P` prepends
  its prefix after matching, so a prefix passed that way can never make a
  fragment match. Candidates are now built fully qualified, and the logic is
  testable without `compgen`, which some bash builds omit.
- A stale lock could be reclaimed by two waiters at once, letting both proceed
  and one delete the other's freshly bound socket. Reclaim now goes through an
  atomic rename, and a holder that cannot record its pid treats the lock as
  lost.
- Socket, lock and SSH ControlPath names collided: `-` was both a legal
  character and the joiner, so host `dev-box` + session `api` and host `dev` +
  session `box-api` shared a socket, and `user@host` and `user_host` shared a
  ControlPath. Keys now carry a checksum of the exact inputs.
- `make install` used `install -D`, a GNU extension absent from the BSD
  install(1) macOS ships. CI now runs it.
- SSH gained `ServerAliveInterval`, `ServerAliveCountMax` and `ConnectTimeout`,
  so a suspended laptop no longer leaves calls hanging on a dead master while
  the forward lock is held.
- The release sequence number ran a minute ahead of the wall clock, which
  would have blacked out re-bridging the same pane for that long. It is now
  two seconds, still clear of any in-flight report.
- `--ttl` requires whole milliseconds, and `--interval 1.2.3` is refused
  instead of silently killing the mirror.
- Documentation corrected: `flock` is no longer required, `ctrl-c` reaches the
  remote agent rather than ending the bridge, and the SSH forward's lifetime
  and teardown are described.

Testing: 92 tests, up from 71. The mirror loop, `--release`, a socket with
nothing listening behind it, an unknown pane id, lock contention and the bash
completion were all untested before. The suite also no longer inherits
`HERDR_*` from the session it is run in, which made local runs differ from CI.

## 0.0.1

First release.

- Bridge one agent from a remote herdr session into the local pane the tool is
  run from, with its lifecycle state mirrored into the local sidebar as
  `<agent>@<host>`.
- `--list` for sessions on a host and agents in a session.
- `--release` to clear a row stranded by a hard kill.
- zsh and bash completion for `<host>:<session>:<pane>`.
- bats suite covering argument handling, socket forwarding, completion output,
  state mapping and teardown, against stub `herdr` and `ssh`.
