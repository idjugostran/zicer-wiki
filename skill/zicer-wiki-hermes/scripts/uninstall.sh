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
#   2. Re-enable the sibling zicer-wiki-context skill in Hermes, if
#      setup.sh had disabled it (skills.disabled) — undoes setup.sh's
#      step 3, doesn't touch any files.
#   3. Remove the daily refresh job setup.sh registers with Hermes's own
#      cron scheduler (and its script under ~/.hermes/scripts/); also
#      cleans up a legacy OS-crontab entry if an older version of this
#      installer left one behind.
#   4. Restart the Hermes gateway, if running and something was removed.
#   5. Restart the Hermes desktop app, if running and something was removed.
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

# Best-effort text patch removing zicer-wiki-context from skills.disabled -
# undoes setup.sh's step 3. Handles the same shapes setup.sh's disable-patch
# can produce (flow list, block list, bare scalar); scoped to the skills:
# block body for the same reason setup.sh's patcher is ("disabled" is a
# generic enough word to plausibly appear elsewhere in a large config).
echo "== 2. Re-enable zicer-wiki-context in Hermes (skills.disabled) =="
CONTEXT_OUTPUT="$(python3 - <<'PYEOF'
import re
import sys
from pathlib import Path

skill_name = "zicer-wiki-context"
config_path = Path.home() / ".hermes" / "config.yaml"

if not config_path.exists():
    print(f"  OK: {config_path} not found - nothing to re-enable")
    sys.exit(0)

text = config_path.read_text(encoding="utf-8")

skills_block = re.search(r"^skills:[ \t]*\n((?:[ \t]+\S.*\n?)*)", text, re.MULTILINE)
if not skills_block:
    print("  OK: no top-level 'skills:' block found - nothing to re-enable")
    sys.exit(0)

block_start, block_end = skills_block.start(1), skills_block.end(1)
block = skills_block.group(1)

if skill_name not in block:
    print(f"  OK: {skill_name} not in skills.disabled - nothing to do")
    sys.exit(0)

def commit(new_block: str, note: str) -> None:
    new_text = text[:block_start] + new_block + text[block_end:]
    config_path.write_text(new_text, encoding="utf-8")
    print(f"  {note}")

# Flow-style list: disabled: [a, "zicer-wiki-context", b]
flow = re.search(r"^(\s*)disabled:\s*\[(.*)\]\s*$", block, re.MULTILINE)
if flow:
    indent, inner = flow.group(1), flow.group(2)
    items = [i.strip() for i in inner.split(",")] if inner.strip() else []
    kept = [i for i in items if i.strip(" '\"") != skill_name]
    if len(kept) == len(items):
        print(f"  WARNING: found {skill_name!r} near skills.disabled but couldn't safely parse it - remove it manually")
        sys.exit(0)
    new_line = f'{indent}disabled: [{", ".join(kept)}]'
    commit(block[:flow.start()] + new_line + block[flow.end():], f"Removed {skill_name} from skills.disabled")
    sys.exit(0)

# Block-style list: disabled:\n  - "zicer-wiki-context"\n  - other
blk = re.search(r"^(\s*)disabled:\s*\n((?:\1\s+- .*\n?)*)", block, re.MULTILINE)
if blk:
    indent, body = blk.group(1), blk.group(2)
    orig_lines = body.splitlines(keepends=True)
    kept_lines = [l for l in orig_lines
                  if not (l.strip().startswith("- ") and l.strip()[2:].strip().strip("'\"") == skill_name)]
    if len(kept_lines) == len(orig_lines):
        print(f"  WARNING: found {skill_name!r} near skills.disabled but couldn't safely parse it - remove it manually")
        sys.exit(0)
    replacement = f"{indent}disabled:\n" + "".join(kept_lines) if kept_lines else f"{indent}disabled: []\n"
    commit(block[:blk.start()] + replacement + block[blk.end():], f"Removed {skill_name} from skills.disabled")
    sys.exit(0)

# Bare scalar: disabled: zicer-wiki-context
scalar = re.search(r"^(\s*)disabled:[ \t]*(\S.*)$", block, re.MULTILINE)
if scalar and scalar.group(2).strip().strip(" '\"") == skill_name:
    indent = scalar.group(1)
    commit(block[:scalar.start()] + f"{indent}disabled: []" + block[scalar.end():],
           f"Removed {skill_name} from skills.disabled")
    sys.exit(0)

print(f"  WARNING: found {skill_name!r} near skills.disabled but couldn't safely parse it - remove it manually")
PYEOF
)"
echo "$CONTEXT_OUTPUT"
CONTEXT_CHANGED=0
echo "$CONTEXT_OUTPUT" | grep -q "^  Removed" && CONTEXT_CHANGED=1

# Remove the Hermes-native cron job by name (hermes cron remove takes an ID,
# not a name - same list-and-scan lookup setup.sh uses), delete its wrapper
# script, and - for anyone who ran an older, OS-crontab-based version of
# this installer - clean up a legacy marker-tagged crontab line too, so
# switching between installer versions never leaves an orphaned job behind
# either way.
echo "== 3. Remove daily refresh job from Hermes's own scheduler =="
JOB_NAME="zicer-wiki-hermes: keep local wiki clone fresh"
CRON_REMOVED=0
if command -v hermes >/dev/null 2>&1; then
  EXISTING_JOB_ID="$(hermes cron list --all 2>/dev/null | awk -v name="$JOB_NAME" '
    /^  [a-f0-9]+ \[/ { id = $1 }
    index($0, "Name:") && index($0, name) { print id; exit }
  ')"
  if [[ -n "$EXISTING_JOB_ID" ]]; then
    hermes cron remove "$EXISTING_JOB_ID" >/dev/null
    CRON_REMOVED=1
    echo "  OK: removed job $EXISTING_JOB_ID"
  else
    echo "  OK: no zicer-wiki-hermes job found in Hermes's scheduler - nothing to remove"
  fi
else
  echo "  Skipped: 'hermes' not found on PATH"
fi
REFRESH_SCRIPT="$HOME/.hermes/scripts/zicer-wiki-hermes-refresh.sh"
if [[ -f "$REFRESH_SCRIPT" ]]; then
  rm -f "$REFRESH_SCRIPT"
  CRON_REMOVED=1
  echo "  Removed $REFRESH_SCRIPT"
fi
# Legacy cleanup: an older installer version registered a plain OS crontab
# entry instead. crontab -l exits non-zero with "no crontab for <user>" when
# none exists - not an error, just nothing to do here.
LEGACY_CRON_MARKER="# zicer-wiki-hermes: keep local wiki clone fresh"
LEGACY_EXISTING="$(crontab -l 2>/dev/null || true)"
if printf '%s\n' "$LEGACY_EXISTING" | grep -qF "$LEGACY_CRON_MARKER"; then
  # `grep -v` exits 1 when it filters out every line (e.g. the marker line
  # was the crontab's only entry) - guard with `|| true` so that doesn't
  # trip set -e.
  LEGACY_FILTERED="$(printf '%s\n' "$LEGACY_EXISTING" | grep -vF "$LEGACY_CRON_MARKER" || true)"
  if [[ -n "$LEGACY_FILTERED" ]]; then
    printf '%s\n' "$LEGACY_FILTERED" | crontab -
  else
    crontab -r
  fi
  CRON_REMOVED=1
  echo "  Removed legacy OS-crontab entry"
fi

if [[ "$DIR_REMOVED" -eq 1 || "$CONFIG_CHANGED" -eq 1 || "$CONTEXT_CHANGED" -eq 1 || "$CRON_REMOVED" -eq 1 ]]; then
  CHANGED=1
else
  CHANGED=0
fi

echo "== 4. Restart Hermes gateway (drop the removed skill) =="
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

echo "== 5. Restart Hermes desktop app (drop the removed skill) =="
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
