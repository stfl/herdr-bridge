# Changelog

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
