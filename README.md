# claude-rc

**Keep [Claude Code](https://claude.com/claude-code) Remote Control sessions alive across crashes, network drops, and reboots — and resume the _same conversation_ each time.**

Claude Code's [Remote Control](https://code.claude.com/docs/en/remote-control) lets you drive a local session from the Claude mobile app or `claude.ai/code`. It's great — until the machine reboots, the network blips, or the process exits. Then:

- the session is gone and doesn't come back on its own,
- restarting it gives you a **new, empty** conversation (resuming the exact one isn't built in), and
- running it unattended under `systemd` tends to fail outright (see [the two gotchas](#the-two-gotchas-that-make-this-actually-work)).

`claude-rc` is a tiny, dependency-light layer (three bash scripts + one systemd timer) that fixes all three. You run **one command in a project folder** and that session stays up forever, in Remote Control, resuming the same chat after every reboot.

```bash
cd ~/code/my-project
rc up                 # start a kept-alive remote-control session named "my-project"
rc up "Infra notes"   # ...or with a custom name
rc ls                 # see what's running
```

---

## Why not just use an existing tool?

There's solid prior art for *parts* of this, but nothing does the whole job:

| Tool | Gives you | Missing for this use case |
|---|---|---|
| [tmux-resurrect](https://github.com/tmux-plugins/tmux-resurrect) + [continuum](https://github.com/tmux-plugins/tmux-continuum) | restore tmux layout/programs after reboot | doesn't resume a **specific Claude conversation**, doesn't enter Remote Control |
| Community `while true; do claude remote-control; done` in tmux | survives crashes & network timeouts | starts a **fresh** session each time — the conversation isn't pinned, and it still hits the systemd gotchas |

The thing nobody had: **after a reboot, the same named conversation comes back, in Remote Control, automatically.** That's an [open feature request](https://github.com/anthropics/claude-code/issues/29748) upstream. `claude-rc` does it by pinning a session UUID per entry and using `claude --remote-control "NAME" --resume <uuid>`.

---

## How it works

```
 ~/.config/claude-rc/desired         systemd --user
 ┌───────────────────────────┐       ┌──────────────────────────────┐
 │ name | dir | uuid         │◀──────│ claude-rc-reconcile.timer     │ every 30s + on boot
 │ name | dir | uuid         │       │   └─ claude-rc-reconcile       │ recreates MISSING sessions
 └───────────────────────────┘       └──────────────────────────────┘
            │ for each desired entry
            ▼
   tmux session "name"  ──running──▶  claude-rc-loop  (while true)
                                         └─ claude --remote-control "name" --resume <uuid>
                                            restarts in 10s on crash / network timeout / auth blip
```

- **`claude-rc-loop`** runs *inside* each tmux session and restarts `claude` whenever it exits. Because the loop outlives `claude`, the tmux session never dies, so crash/timeout recovery is instant.
- **`claude-rc-reconcile`** (a systemd timer, every 30s + on boot) only (re)creates a tmux session that is *missing* — e.g. after a reboot. It never kills anything, and it skips a UUID that's already live in another process so it won't duplicate a session you're actively using.
- **`rc`** is the CLI you actually use (`up` / `down` / `ls` / `attach`). `rc up` assigns a UUID (via `uuidgen`) and writes `name|dir|uuid` to the desired-state file.
- **UUID pinning**: the loop uses `--resume <uuid>` if a transcript exists, else `--session-id <uuid>` to pin a fresh one — so the conversation identity is stable forever.

### The two gotchas that make this actually work

These cost real debugging time; both are baked into the shipped systemd unit:

1. **`KillMode=process`** — the reconcile service is `Type=oneshot`. Without `KillMode=process`, systemd tears down the unit's cgroup when the script exits and **kills the tmux sessions it just spawned**, producing a restart loop every 30s. With it, the spawned tmux server survives.
2. **`CLAUDE_TRUST_WORKSPACE=1`** — otherwise Claude Code's workspace-trust prompt fires and **hangs** unattended `claude --remote-control` under systemd ([claude-code #53606](https://github.com/anthropics/claude-code/issues/53606), affects v2.1.119+).

---

## Requirements

- Linux with **systemd** (uses `systemctl --user`)
- **tmux**, **uuidgen** (`uuid-runtime` / `util-linux`), **bash**
- **Claude Code** on a plan that supports Remote Control (Pro, Max, Team, or Enterprise). On **Team/Enterprise** an admin must enable the Remote Control toggle first — it's off by default.
- Logged in with `claude` (via `/login`, claude.ai OAuth — **not** an API key).

## Install

```bash
git clone https://github.com/RyKaT07/claude-rc.git
cd claude-rc
./install.sh
```

The installer copies the scripts to `~/.local/bin`, installs the systemd user units, enables the timer, and enables **linger** (so your sessions come back after a reboot even without logging in — this step may ask for `sudo`).

Make sure `~/.local/bin` is on your `PATH`.

## Usage

```bash
rc up [name]      # register the current dir (+ a UUID) and start it in Remote Control now
rc down [name]    # stop the tmux session and unregister it
rc ls             # list desired sessions: live? + short UUID + dir
rc attach [name]  # attach to the tmux session locally (Ctrl-b d to detach)
rc reconcile      # run the reconciler once (normally automatic)
```

`name` defaults to the current folder's name. Then open the **Claude app** or **claude.ai/code** and your session is in the list.

## Notes & limitations

- **After a reboot, give the app a minute or two.** The local side comes up within ~30s, but the relay's session list can take a little while to repopulate.
- **Stale/duplicate entries** may briefly appear in the app after lots of restarts; they time out server-side on their own.
- Remote Control itself exits after roughly **10 minutes of no network** ([per the docs](https://code.claude.com/docs/en/remote-control)); the loop just restarts it when connectivity returns.
- This manages **inline** remote-control sessions (one conversation each). If you'd rather have one multi-session server per directory, use `claude remote-control` (server mode) directly.

## Uninstall

```bash
./uninstall.sh            # remove scripts + units, keep your config and running sessions
./uninstall.sh --purge    # also kill sessions and delete ~/.config/claude-rc
```

## Credits

Builds on the community "tmux + restart loop" pattern for Remote Control and on the prior art of tmux-resurrect/continuum. The workspace-trust and reboot-persistence pain points are tracked upstream in claude-code issues [#53606](https://github.com/anthropics/claude-code/issues/53606), [#29748](https://github.com/anthropics/claude-code/issues/29748), and [#28914](https://github.com/anthropics/claude-code/issues/28914).

## License

[MIT](LICENSE)
