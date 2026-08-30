#!/usr/bin/env bash
# Uninstaller for the zicer-wiki-hermes Hermes skill — reverses exactly
# what scripts/setup.sh does, back to a clean state:
#
#   curl -fsSL https://raw.githubusercontent.com/idjugostran/zicer-wiki/master/skill/zicer-wiki-hermes/scripts/uninstall.sh | bash
#
# What it does, in order:
#   0. Delete the installed checkout (default ~/Zicer) — the wiki/ +
#      skill/ data setup.sh cloned onto this machine.
#   1. Unregister the skill from Hermes (skills.external_dirs).
#   2. Remove the daily refresh cron job setup.sh installs.
#   3. Restart the Hermes gateway, if running and something was removed.
#   4. Restart the Hermes desktop app, if running and something was removed.
#
# Scope: this only undoes the *install* — the local checkout, the Hermes
# registration, and the cron job. It does not touch Hermes's own
# logs/conversation history (those may still mention Zicer from past
# replies), and it never touches the wiki's source repo
# (github.com/idjugostran/zicer-wiki) or any dev clone of it — only the
# installed copy on *this* machine.
#
# Idempotent — safe to re-run: anything already gone/unregistered is reported
# as already-clean, never an error.
#
# Env vars (for the curl|bash form):
#   ZICER_INSTALL_DIR   dir to remove (default: ~/Zicer — must match
#                        whatever --dir/ZICER_INSTALL_DIR setup.sh
#                        was originally run with)
# CLI flags (only usable once you have a local copy):
#   --dir PATH    same as ZICER_INSTALL_DIR
#   -y, --yes     skip the confirmation prompt (needed for curl|bash)

set -euo pipefail

INSTALL_DIR="${ZICER_INSTALL_DIR:-$HOME/Zicer}"
ASSUME_YES=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir) INSTALL_DIR="$2"; shift 2 ;;
    -y|--yes) ASSUME_YES=1; shift ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

echo "This will remove:"
echo "  - $INSTALL_DIR (the installed wiki + skill checkout)"
echo "  - its entry in $HOME/.hermes/config.yaml (skills.external_dirs)"
echo "  - its daily refresh cron job (if registered)"
if [[ "$ASSUME_YES" -eq 0 ]]; then
  if [[ -r /dev/tty ]]; then
    read -r -p "Continue? [y/N] " REPLY < /dev/tty || REPLY=""
  else
    echo "No terminal to confirm on - re-run with -y/--yes to proceed non-interactively." >&2
    exit 1
  fi
  if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
    echo "Aborted - nothing changed."
    exit 0
  fi
fi

# Only delete if it actually looks like a zicer-wiki checkout, so a
# mistyped/reused --dir never nukes an unrelated directory.
echo "== 0. Remove installed checkout ($INSTALL_DIR) =="
DIR_REMOVED=0
if [[ ! -e "$INSTALL_DIR" ]]; then
  echo "  OK: $INSTALL_DIR does not exist - nothing to remove"
elif [[ ! -d "$INSTALL_DIR/.git" ]] || [[ ! -d "$INSTALL_DIR/skill/zicer-wiki-hermes" ]]; then
  echo "  WARNING: $INSTALL_DIR doesn't look like a zicer-wiki checkout" >&2
  echo "           (missing .git or skill/zicer-wiki-hermes) - refusing to delete it." >&2
  echo "           If this really is the right directory, remove it yourself: rm -rf \"$INSTALL_DIR\"" >&2
else
  SIZE="$(du -sh "$INSTALL_DIR" 2>/dev/null | cut -f1)"
  rm -rf "$INSTALL_DIR"
  DIR_REMOVED=1
  echo "  Removed ($SIZE freed)"
fi

# Best-effort text patch of ~/.hermes/config.yaml, undoing whichever of
# setup.sh's insertion shapes (flow-list or block-list) is present. Anything
# it can't safely parse is left alone with a manual instruction instead of a
# risky edit.
echo "== 1. Unregister skill from Hermes (skills.external_dirs) =="
CONFIG_OUTPUT="$(python3 - "$INSTALL_DIR/skill" <<'PYEOF'
import re
import sys
from pathlib import Path

skill_parent_dir = sys.argv[1]
config_path = Path.home() / ".hermes" / "config.yaml"

if not config_path.exists():
    print(f"  OK: {config_path} not found - nothing to unregister")
    sys.exit(0)

text = config_path.read_text(encoding="utf-8")

if skill_parent_dir not in text:
    print(f"  OK: {skill_parent_dir} not registered in skills.external_dirs - nothing to do")
    sys.exit(0)

changed = False

# Flow-style list: external_dirs: [a, "path", b]
def strip_flow(m):
    global changed
    indent, inner = m.group(1), m.group(2)
    items = [i.strip() for i in inner.split(",")] if inner.strip() else []
    kept = [i for i in items if i.strip(" '\"") != skill_parent_dir]
    if len(kept) != len(items):
        changed = True
    return f'{indent}external_dirs: [{", ".join(kept)}]'

text = re.sub(r'^(\s*)external_dirs:\s*\[(.*)\]\s*$', strip_flow, text, flags=re.MULTILINE)

# Block-style list: external_dirs:\n  - "path"\n  - other
def strip_block(m):
    global changed
    indent, body = m.group(1), m.group(2)
    kept_lines = []
    for line in body.splitlines(keepends=True):
        item = line.strip()
        if item.startswith("- ") and item[2:].strip().strip("'\"") == skill_parent_dir:
            changed = True
            continue
        kept_lines.append(line)
    if not kept_lines:
        return f'{indent}external_dirs: []\n'
    return f'{indent}external_dirs:\n' + "".join(kept_lines)

text = re.sub(r'^(\s*)external_dirs:\s*\n((?:\1\s+- .*\n?)*)', strip_block, text, flags=re.MULTILINE)

if changed:
    config_path.write_text(text, encoding="utf-8")
    print(f"  Removed {skill_parent_dir} from skills.external_dirs")
else:
    print(f"  WARNING: found {skill_parent_dir} in config.yaml but couldn't safely remove it")
    print(f"           (unrecognized shape) - remove it manually from skills.external_dirs")
PYEOF
)"
echo "$CONFIG_OUTPUT"
CONFIG_CHANGED=0
echo "$CONFIG_OUTPUT" | grep -q "^  Removed" && CONFIG_CHANGED=1

# Strip exactly the marker-tagged crontab line, leaving every other entry
# (including any completely unrelated cron jobs the user has) untouched.
echo "== 2. Remove daily refresh cron job =="
CRON_MARKER="# zicer-wiki-hermes: keep local wiki clone fresh"
CRON_REMOVED=0
# crontab -l exits non-zero with "no crontab for <user>" when none exists -
# not an error, just nothing to do here.
EXISTING="$(crontab -l 2>/dev/null || true)"
if ! printf '%s\n' "$EXISTING" | grep -qF "$CRON_MARKER"; then
  echo "  OK: no zicer-wiki-hermes cron entry found - nothing to remove"
else
  # `grep -v` exits 1 when it filters out every line (e.g. the marker line
  # was the crontab's only entry) - guard with `|| true` so that doesn't
  # trip set -e.
  FILTERED="$(printf '%s\n' "$EXISTING" | grep -vF "$CRON_MARKER" || true)"
  if [[ -n "$FILTERED" ]]; then
    printf '%s\n' "$FILTERED" | crontab -
  else
    # Nothing left at all - remove the crontab outright rather than
    # installing an empty one (some crontab implementations reject that).
    crontab -r
  fi
  CRON_REMOVED=1
  echo "  Removed cron entry"
fi

if [[ "$DIR_REMOVED" -eq 1 || "$CONFIG_CHANGED" -eq 1 || "$CRON_REMOVED" -eq 1 ]]; then
  CHANGED=1
else
  CHANGED=0
fi

echo "== 3. Restart Hermes gateway (drop the removed skill) =="
if [[ "$CHANGED" -eq 0 ]]; then
  echo "  Skipped: nothing changed this run, no need to restart"
elif ! command -v hermes >/dev/null 2>&1; then
  echo "  Skipped: 'hermes' not found on PATH"
elif ! hermes gateway status >/dev/null 2>&1; then
  echo "  Skipped: gateway not installed/running here (nothing to restart)"
else
  if hermes gateway restart; then
    echo "  OK: gateway restarted"
  else
    echo "  WARNING: 'hermes gateway restart' failed - restart it yourself:"
    echo "           hermes gateway restart"
  fi
fi

echo "== 4. Restart Hermes desktop app (drop the removed skill) =="
if [[ "$CHANGED" -eq 0 ]]; then
  echo "  Skipped: nothing changed this run, no need to restart"
elif ! pgrep -f "hermes-agent/apps/desktop/release" >/dev/null 2>&1; then
  echo "  Skipped: desktop app not running here"
else
  echo "  Desktop app is running - quitting..."
  QUIT_OK=0
  if command -v osascript >/dev/null 2>&1; then
    osascript -e 'tell application "Hermes" to quit' >/dev/null 2>&1 && QUIT_OK=1
  fi
  if [[ "$QUIT_OK" -eq 0 ]]; then
    pkill -f "hermes-agent/apps/desktop/release" 2>/dev/null || true
  fi
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    pgrep -f "hermes-agent/apps/desktop/release" >/dev/null 2>&1 || break
    sleep 1
  done
  if pgrep -f "hermes-agent/apps/desktop/release" >/dev/null 2>&1; then
    echo "  WARNING: desktop app still running after 10s - not relaunching."
    echo "           Close it yourself if you want it back up: hermes desktop --skip-build"
  else
    echo "  OK: desktop app closed"
    if command -v hermes >/dev/null 2>&1; then
      nohup hermes desktop --skip-build >/tmp/hermes-desktop-restart.log 2>&1 &
      disown
      echo "  Relaunching without the skill (log: /tmp/hermes-desktop-restart.log)"
    fi
  fi
fi

echo "== Done =="
if [[ "$CHANGED" -eq 1 ]]; then
  echo "Removed. Re-run setup.sh any time to reinstall."
else
  echo "Nothing to do - no trace of this skill was found on this machine."
fi
