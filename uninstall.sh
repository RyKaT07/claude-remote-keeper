#!/usr/bin/env bash
# uninstall.sh — remove claude-rc. Leaves ~/.config/claude-rc/desired (your data)
# and any running tmux sessions untouched. Pass --purge to also remove them.
set -euo pipefail

BIN="$HOME/.local/bin"
UNIT="$HOME/.config/systemd/user"
CONF="$HOME/.config/claude-rc"
PURGE="${1:-}"

echo "==> Uninstalling claude-rc"
systemctl --user disable --now claude-rc-reconcile.timer 2>/dev/null || true
systemctl --user disable --now claude-rc-reconcile.service 2>/dev/null || true
rm -f "$UNIT/claude-rc-reconcile.service" "$UNIT/claude-rc-reconcile.timer"
systemctl --user daemon-reload
rm -f "$BIN/rc" "$BIN/claude-rc-loop" "$BIN/claude-rc-reconcile"

if [ "$PURGE" = "--purge" ]; then
  echo "==> --purge: killing live sessions and removing config"
  if command -v tmux >/dev/null && [ -f "$CONF/desired" ]; then
    while IFS='|' read -r name _; do
      [ -z "$name" ] || [ "${name#\#}" != "$name" ] && continue
      tmux kill-session -t "=$name" 2>/dev/null || true
    done < "$CONF/desired"
  fi
  rm -rf "$CONF"
fi

echo "==> Done. (Your tmux sessions, if any, keep running unless you passed --purge.)"
