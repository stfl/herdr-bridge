# herdr-bridge

Show a remote [herdr](https://herdr.dev) agent inside a local herdr pane — in
the local sidebar, next to the local ones.

```
  laptop                             workbox
  ┌─ herdr ───────────────────────┐  ┌─ herdr · session "api" ──────┐
  │ ● claude           web        │  │                              │
  │ ● claude           billing    │  │ ● claude   auth middleware   │
  │ ● claude@workbox   auth mw ───┼──┼─▶ w5:p1                      │
  │                    ▲          │  │                              │
  └────────────────────┼──────────┘  └──────────────────────────────┘
                       └── one sidebar, both machines
```

## Why

herdr keeps every named session in its own server, and its sidebar renders
exactly one of them. Reaching a session on another machine means
`herdr --remote host` (a second, separate UI) or `ssh host && herdr` (a nested
TUI inside a pane, with two sidebars, two tab bars and a contested prefix
key). Either way the remote agents stay outside the local agent panel, so
"which of my agents needs me?" has to be answered once per machine.

`herdr-bridge` answers it once. A remote agent occupies a local pane and
appears in the local sidebar as `claude@workbox`, with live state — idle,
working, blocked — and the title of what it is working on.

## How

Nothing is nested and nothing is patched. The tool composes three things herdr
already exposes:

1. **Socket forwarding.** A herdr session is reachable through two unix
   sockets, `herdr.sock` and `herdr-client.sock`. Both are forwarded over one
   multiplexed SSH connection, after which the local `herdr` CLI drives the
   remote server by pointing `HERDR_SOCKET_PATH` at them.
2. **Direct terminal attach.** `herdr agent attach` streams one server-owned
   terminal into the terminal it is run from. Run inside a local pane, the
   remote agent lands in that pane. Because it is an attach and not a second
   TUI, `ctrl+b` still belongs to the local client.
3. **Agent reporting.** `herdr pane report-agent` and `herdr pane
   report-metadata` — the same API herdr's own integrations use — publish the
   remote agent's identity, lifecycle state and title onto the local pane. A
   background loop keeps them in step and withdraws the row on exit.

Every call is public herdr CLI surface. There is no patched binary, no
protocol reverse-engineering and no daemon.

## Install

**Nix (flake)**

```nix
inputs.herdr-bridge.url = "github:stfl/herdr-bridge";
# then, in your packages:
inputs.herdr-bridge.packages.${system}.default
```

or, to try it once:

```sh
nix run github:stfl/herdr-bridge -- --help
```

**Anything else**

```sh
git clone https://github.com/stfl/herdr-bridge
cd herdr-bridge
sudo make install            # PREFIX=/usr/local by default
```

`make install` also installs zsh and bash completions.

**Requirements:** `herdr`, `ssh`, `jq`, `flock` (util-linux), `awk`. The tool
checks for each and names the missing one. `herdr` is deliberately taken from
`PATH` rather than pinned, because it has to speak to whichever herdr owns
your session.

## Use

Run it from inside a herdr pane — that pane is the one the remote agent takes
over.

```sh
herdr-bridge workbox:api            # the session's only agent
herdr-bridge workbox:api:w5:p1      # a specific remote pane
herdr-bridge workbox                 # the host's "default" session

herdr-bridge --list workbox          # sessions on a host
herdr-bridge --list workbox:api     # agents in a session
```

Completion walks `host` → `session` → `agent`, so an agent is picked by what
it is doing rather than by its pane id:

```
$ herdr-bridge workbox:api:<TAB>
w5:p1  -- claude · working · refactor the auth middleware
```

Hosts come from `HERDR_BRIDGE_HOSTS` (space separated) and from your
`~/.ssh/config`, minus the local machine.

Forwarded sockets and locks live in `$XDG_RUNTIME_DIR/herdr-bridge`, or in
`/tmp/herdr-bridge-$uid` when that path is too long to hold a unix socket —
which is the case on macOS, where the per-user temp directory is already most
of the 108-byte budget. `HERDR_BRIDGE_RUNTIME_DIR` overrides both.

Detach the same way you would from any attach, or press `ctrl-c`; the row is
withdrawn from the sidebar as you leave. A hard kill can strand a row, and
`herdr-bridge --release` clears it from the pane it is stuck on.

### Showing the host in the sidebar

The bridged row already reads `claude@workbox`. To render the host as its own
field, the mirror also publishes `host` and `session` tokens:

```toml
[ui.sidebar.agents]
rows = [
  ["state_icon", "workspace", "tab"],
  ["state_text", "agent", "$host"],
]
```

## Limitations

- **Agents, not workspaces.** You get one local pane per remote agent, placed
  in your own layout. The remote workspace tree is not grafted onto the local
  sidebar.
- **State is polled**, once a second by default (`--interval`). herdr has no
  subscription for another server's agent state.
- **One pane, one agent.** Bridging three remote agents means three panes,
  each running the tool. They share a single SSH connection and a single
  forward per session.
- **The remote host needs `herdr` on a non-interactive `PATH`**, since the
  session is queried over `ssh host herdr ...`.

## Development

```sh
make lint        # shellcheck
make test        # bats
nix flake check  # both, hermetically
```

The suite runs against stub `herdr` and `ssh` binaries on `PATH`, so it needs
no herdr server, no network and no second machine. The stubs reproduce the
real CLI's quirks on purpose — including `herdr status server` reporting a
dead socket while still exiting `0`, which is the kind of thing that silently
breaks a liveness check.

## License

MIT
