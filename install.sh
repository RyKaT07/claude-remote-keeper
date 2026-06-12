#!/usr/bin/env bash
# install.sh — install claude-rc for the current user (no root needed, except
# enabling linger). Copies scripts to ~/.local/bin and systemd user units, then
# enables the reconcile timer so sessions are restored on boot and kept alive.
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
BIN="$HOME/.local/bin"
UNIT="$HOME/.config/systemd/user"
CONF="$HOME/.config/claude-rc"

echo "==> Installing claude-rc"

# --- preflight ---------------------------------------------------------------
command -v tmux >/dev/null || { echo "ERROR: tmux is not installed."; exit 1; }
command -v uuidgen >/dev/null || { echo "ERROR: uuidgen is not installed (package: uuid-runtime/util-linux)."; exit 1; }
command -v systemctl >/dev/null || { echo "ERROR: this tool requires systemd (systemctl --user)."; exit 1; }
if ! command -v claude >/dev/null; then
  echo "WARNING: 'claude' is not on PATH right now. Make sure Claude Code is installed"
  echo "         and on PATH for the systemd user session before sessions will start."
fi

# --- copy files --------------------------------------------------------------
mkdir -p "$BIN" "$UNIT" "$CONF"
install -m 0755 "$SRC/bin/rc"                  "$BIN/rc"
install -m 0755 "$SRC/bin/claude-rc-loop"      "$BIN/claude-rc-loop"
install -m 0755 "$SRC/bin/claude-rc-reconcile" "$BIN/claude-rc-reconcile"
install -m 0644 "$SRC/systemd/claude-rc-reconcile.service" "$UNIT/claude-rc-reconcile.service"
install -m 0644 "$SRC/systemd/claude-rc-reconcile.timer"   "$UNIT/claude-rc-reconcile.timer"
[ -f "$CONF/desired" ] || { install -m 0644 "$SRC/examples/desired.example" "$CONF/desired"; echo "    created $CONF/desired"; }

# bash tab-completion (loaded automatically by the bash-completion package)
COMPL="$HOME/.local/share/bash-completion/completions"
mkdir -p "$COMPL"
install -m 0644 "$SRC/completions/rc.bash" "$COMPL/rc"
echo "    installed bash completion (open a new shell, or: source $COMPL/rc)"

# --- enable services ---------------------------------------------------------
systemctl --user daemon-reload
systemctl --user enable --now claude-rc-reconcile.timer
systemctl --user enable claude-rc-reconcile.service
echo "    systemd user timer enabled."

# --- linger (so sessions come back after reboot WITHOUT you logging in) ------
if ! loginctl show-user "$USER" 2>/dev/null | grep -q 'Linger=yes'; then
  echo "==> Enabling linger so sessions survive logout/reboot..."
  if ! loginctl enable-linger "$USER" 2>/dev/null; then
    echo "    Could not enable linger automatically. Run once with sudo:"
    echo "       sudo loginctl enable-linger $USER"
  fi
fi

# --- PATH hint ---------------------------------------------------------------
case ":$PATH:" in
  *":$BIN:"*) ;;
  *) echo "NOTE: $BIN is not on your PATH. Add to your shell rc:"
     echo "      export PATH=\"\$HOME/.local/bin:\$PATH\"";;
esac

cat <<'EOF'

==> Done. Usage:
    cd /path/to/your/project
    rc up                 # start a kept-alive remote-control session (named after the folder)
    rc up "My Session"    # ...or with a custom name
    rc ls                 # list sessions + live state + UUID
    rc attach "My Session"
    rc down "My Session"

Open the Claude app or claude.ai/code to connect. After a reboot, give the app a
minute or two to repopulate the session list.
EOF
