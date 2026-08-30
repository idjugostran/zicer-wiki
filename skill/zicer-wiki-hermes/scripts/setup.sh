#!/usr/bin/env bash
# Standalone installer for the zicer-wiki-hermes Hermes skill.
#
# Designed to be run as a one-liner straight from GitHub, with nothing
# pre-cloned on the machine:
#
#   curl -fsSL https://raw.githubusercontent.com/idjugostran/zicer-wiki/master/skill/zicer-wiki-hermes/scripts/setup.sh | bash
#
# Everything is self-contained: it does a SPARSE clone of just the data the
# skill actually reads (wiki/, skill/ — NOT raw/, which is the archival
# source-video material the skill never opens, and not bin/ either, since
# wiki/index.md is committed pre-generated and this installer never runs
# Python for wiki generation), registers the skill with Hermes
# (skills.external_dirs), and installs a daily cron job that re-invokes this
# same script from the local clone so the wiki stays fresh. Unlike the
# sibling `zicer-wiki-context` skill (which fetches the wiki over HTTPS on
# every mention, no local data), this Hermes-only variant pre-clones once and
# refreshes on a schedule instead of fetching remotely on every invocation.
#
# Idempotent — safe to re-run any time (by hand, or by the daily cron tick
# this script itself installs): re-running just fast-forwards to the latest
# wiki content (so newly added pages show up), never re-registers a path
# that's already in skills.external_dirs, and never adds a duplicate cron
# line (matched and replaced via a marker comment). A run with nothing new
# upstream is a no-op past the git fetch.
#
# Override defaults via env vars (useful for the curl|bash form, where
# there's no way to pass CLI flags before the script exists locally):
#   ZICER_REPO_URL     git remote to clone (default: see REPO_URL below)
#   ZICER_INSTALL_DIR  where to clone it (default: ~/Zicer)
#   ZICER_CRON_TIME    daily refresh time, 24h HH:MM, local time (default: 04:17)
# CLI flags (only usable once you have a local copy, e.g. `./setup.sh --no-register`):
#   --dir PATH          same as ZICER_INSTALL_DIR
#   --repo URL          same as ZICER_REPO_URL
#   --no-register       skip the Hermes registration step (clone/update only)
#   --no-cron           skip installing/updating the daily refresh cron job
#   --cron-time HH:MM   same as ZICER_CRON_TIME
#
# --no-register and --no-cron are independent — skipping one doesn't skip
# the other (a caller might want the clone kept fresh without touching
# Hermes's config, or vice versa). The one place they're NOT independent:
# if --no-register was passed, steps 4/5 (restarting Hermes) are skipped
# too, same as before cron existed — restarting Hermes to pick up a skill
# that was never registered with it has nothing to do.
#
# What it does, in order (see the comment above each numbered step below for
# the full detail on that step):
#   0. Sparse-clone/update just wiki/, skill/ (no raw/, no bin/).
#   1. Check the `hermes` CLI is on PATH.
#   2. Register the skill with Hermes (skills.external_dirs).
#   3. Register a daily cron job that re-runs this script from the local
#      clone to pull updates and re-sync Hermes if anything changed.
#   4. Restart the Hermes gateway, if running and something changed.
#   5. Restart the Hermes desktop app, if running and something changed.
#
# To remove everything this script installs, see uninstall.sh in this same
# directory.

set -euo pipefail

REPO_URL="${ZICER_REPO_URL:-https://github.com/idjugostran/zicer-wiki.git}"
INSTALL_DIR="${ZICER_INSTALL_DIR:-$HOME/Zicer}"
CRON_TIME="${ZICER_CRON_TIME:-04:17}"
DO_REGISTER=1
DO_CRON=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir) INSTALL_DIR="$2"; shift 2 ;;
    --repo) REPO_URL="$2"; shift 2 ;;
    --no-register) DO_REGISTER=0; shift ;;
    --no-cron) DO_CRON=0; shift ;;
    --cron-time) CRON_TIME="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [[ ! "$CRON_TIME" =~ ^([0-1][0-9]|2[0-3]):([0-5][0-9])$ ]]; then
  echo "ERROR: --cron-time/ZICER_CRON_TIME must be 24h HH:MM (got: $CRON_TIME)" >&2
  exit 2
fi

# Cone-mode sparse-checkout of just wiki/ and skill/ — raw/, bin/, config/,
# assets/ never hit disk. wiki/index.md is committed (not gitignored), so
# there's nothing to generate client-side. Root-level loose files (SCHEMA.md,
# .gitignore) come along for free either way: cone mode always includes
# files sitting directly at the repo root, only directories need to be
# listed explicitly - harmless, a few KB, unused by this installer or the
# skill but kept for anyone poking around the checkout by hand.
#
# Note: skill/ is checked out whole, so any other skill directories that
# live alongside this one (e.g. the sibling zicer-wiki-context) come along
# too and end up registered with Hermes as well - that's inherited, generic
# behavior from the original installer (it was never scoped to just this
# skill), not something introduced here.
echo "== 0. Sparse clone/update (wiki/, skill/ only — no raw/, no bin/) =="
CHANGED=0
if [[ -d "$INSTALL_DIR/.git" ]]; then
  echo "  Existing checkout found at $INSTALL_DIR - fetching updates..."
  # Re-apply the sparse-checkout pattern on every run, not just at initial
  # clone: a plain `git pull` never shrinks/grows which paths are checked
  # out, so an install made before this pattern dropped bin/ would otherwise
  # keep carrying a now-pointless bin/ forever. Idempotent - a no-op if the
  # pattern already matches.
  git -C "$INSTALL_DIR" sparse-checkout set wiki skill
  BEFORE="$(git -C "$INSTALL_DIR" rev-parse HEAD)"
  git -C "$INSTALL_DIR" pull --ff-only
  AFTER="$(git -C "$INSTALL_DIR" rev-parse HEAD)"
  if [[ "$BEFORE" == "$AFTER" ]]; then
    echo "  OK: already up to date ($AFTER)"
  else
    CHANGED=1
    N=$(git -C "$INSTALL_DIR" rev-list --count "$BEFORE..$AFTER")
    echo "  Updated: $N new commit(s), $BEFORE -> $AFTER"
    echo "  Changed files:"
    git -C "$INSTALL_DIR" diff --name-status "$BEFORE" "$AFTER" | sed 's/^/    /'
  fi
elif [[ -e "$INSTALL_DIR" ]]; then
  echo "  ERROR: $INSTALL_DIR exists and is not a git checkout of this repo." >&2
  echo "         Refusing to touch it - move it aside or pick a different --dir." >&2
  exit 1
else
  echo "  Cloning (sparse) $REPO_URL -> $INSTALL_DIR"
  git clone --filter=blob:none --no-checkout --depth 1 "$REPO_URL" "$INSTALL_DIR"
  git -C "$INSTALL_DIR" sparse-checkout init --cone
  git -C "$INSTALL_DIR" sparse-checkout set wiki skill
  DEFAULT_BRANCH="$(git -C "$INSTALL_DIR" remote show origin | sed -n '/HEAD branch/s/.*: //p')"
  git -C "$INSTALL_DIR" checkout "$DEFAULT_BRANCH"
  CHANGED=1
  echo "  OK: cloned at $(git -C "$INSTALL_DIR" rev-parse HEAD)"
fi
INSTALLED_SIZE="$(du -sh "$INSTALL_DIR" 2>/dev/null | cut -f1)"
echo "  On-disk size: $INSTALLED_SIZE (raw/ excluded)"

# Can't install Hermes itself from here - that's a separate onboarding step.
# This check is unconditional (even under --no-register/--no-cron) - carried
# over unchanged from the original installer.
echo "== 1. hermes CLI =="
if command -v hermes >/dev/null 2>&1; then
  echo "  OK: $(hermes --version 2>&1 | head -1)"
else
  echo "  ERROR: 'hermes' not found on PATH. Install Hermes first:"
  echo "         https://hermes.nousresearch.com"
  exit 1
fi

# Best-effort text patch of ~/.hermes/config.yaml - handles the YAML shapes
# below and never guesses past what it can safely recognize; anything else
# gets a manual instruction instead of a risky edit.
echo "== 2. Register skill with Hermes (skills.external_dirs) =="
if [[ "$DO_REGISTER" -eq 0 ]]; then
  echo "  Skipped (--no-register)"
else
  python3 - "$INSTALL_DIR/skill" <<'PYEOF'
import re
import sys
from pathlib import Path

skill_parent_dir = sys.argv[1]
config_path = Path.home() / ".hermes" / "config.yaml"

if not config_path.exists():
    print(f"  WARNING: {config_path} not found - skipping (run 'hermes' once to create it, then re-run this script)")
    sys.exit(0)

text = config_path.read_text(encoding="utf-8")

if skill_parent_dir in text:
    print(f"  OK: {skill_parent_dir} already registered in skills.external_dirs")
    sys.exit(0)

# Case 1: empty flow-style list -> "external_dirs: []"
flow_empty = re.search(r"^(\s*)external_dirs:\s*\[\]\s*$", text, re.MULTILINE)
if flow_empty:
    indent = flow_empty.group(1)
    new_line = f'{indent}external_dirs: ["{skill_parent_dir}"]'
    text = text[:flow_empty.start()] + new_line + text[flow_empty.end():]
    config_path.write_text(text, encoding="utf-8")
    print(f"  Added {skill_parent_dir} to skills.external_dirs (was empty)")
    sys.exit(0)

# Case 2: non-empty flow-style list -> "external_dirs: [a, b]"
flow_nonempty = re.search(r"^(\s*)external_dirs:\s*\[(.*)\]\s*$", text, re.MULTILINE)
if flow_nonempty:
    indent, inner = flow_nonempty.group(1), flow_nonempty.group(2).strip()
    new_inner = f'{inner}, "{skill_parent_dir}"' if inner else f'"{skill_parent_dir}"'
    new_line = f"{indent}external_dirs: [{new_inner}]"
    text = text[:flow_nonempty.start()] + new_line + text[flow_nonempty.end():]
    config_path.write_text(text, encoding="utf-8")
    print(f"  Added {skill_parent_dir} to skills.external_dirs (existing flow list)")
    sys.exit(0)

# Case 3: block-style list -> "external_dirs:\n  - foo\n  - bar"
block = re.search(r"^(\s*)external_dirs:\s*\n((?:\1\s+- .*\n?)*)", text, re.MULTILINE)
if block:
    indent = block.group(1)
    item_indent = indent + "  "
    insert_at = block.end()
    new_item = f'{item_indent}- "{skill_parent_dir}"\n'
    text = text[:insert_at] + new_item + text[insert_at:]
    config_path.write_text(text, encoding="utf-8")
    print(f"  Added {skill_parent_dir} to skills.external_dirs (existing block list)")
    sys.exit(0)

# Case 4: a "skills:" block exists but has no "external_dirs:" key at all.
# Hermes' config.yaml only persists keys the user has explicitly touched, so
# a config that's never had its skill dirs configured commonly looks like:
#   skills:
#     creation_nudge_interval: 15
# with no external_dirs line to patch at all. Insert one as the first
# child of the skills: block, matching the indentation of its siblings.
skills_block = re.search(r"^skills:[ \t]*\n((?:[ \t]+\S.*\n?)*)", text, re.MULTILINE)
if skills_block and "external_dirs" not in skills_block.group(0):
    body = skills_block.group(1)
    first_line_indent_match = re.match(r"[ \t]+", body) if body else None
    item_indent = first_line_indent_match.group(0) if first_line_indent_match else "  "
    insert_at = skills_block.start(1)
    new_line = f'{item_indent}external_dirs: ["{skill_parent_dir}"]\n'
    text = text[:insert_at] + new_line + text[insert_at:]
    config_path.write_text(text, encoding="utf-8")
    print(f"  Added {skill_parent_dir} to skills.external_dirs (key didn't exist yet)")
    sys.exit(0)

# Case 5: no "skills:" top-level key at all - append a fresh block.
if not re.search(r"^skills:[ \t]*$", text, re.MULTILINE):
    sep = "" if text.endswith("\n") else "\n"
    text = text + sep + f'skills:\n  external_dirs: ["{skill_parent_dir}"]\n'
    config_path.write_text(text, encoding="utf-8")
    print(f"  Added {skill_parent_dir} to skills.external_dirs (created skills: block)")
    sys.exit(0)

print("  WARNING: could not find a recognizable 'external_dirs:' shape in")
print(f"           {config_path} - add it manually under skills.external_dirs:")
print(f'             - "{skill_parent_dir}"')
PYEOF
fi

# Cron entry is a single line, tagged with a unique marker comment so it can
# be found/replaced/removed precisely (standard "strip by marker, then
# re-append" idempotent pattern - same approach ansible's cron module uses).
# `#` starts a shell comment wherever it appears unquoted, so appending the
# marker at the end of the command is inert at execution time and only
# matters for `grep`.
echo "== 3. Register daily cron job (keep local clone fresh) =="
CRON_MARKER="# zicer-wiki-hermes: keep local wiki clone fresh"
if [[ "$DO_CRON" -eq 0 ]]; then
  echo "  Skipped (--no-cron)"
else
  SCRIPT_PATH="$INSTALL_DIR/skill/zicer-wiki-hermes/scripts/setup.sh"
  CRON_HOUR="${CRON_TIME%%:*}"
  CRON_MIN="${CRON_TIME##*:}"

  # Replicate this run's --dir/--repo so a customized install stays
  # customized on every unattended tick (re-downloading over curl each day
  # would defeat the point of cron - reuse the now-local clone instead), and
  # --no-register if this run had it, so an install that explicitly opted
  # out of touching Hermes doesn't have that silently reversed by cron.
  # --no-cron is deliberately never replicated - a cron tick that re-runs
  # itself with --no-cron would deregister its own cron job.
  CRON_CMD_ARGS=(--dir "$INSTALL_DIR" --repo "$REPO_URL")
  [[ "$DO_REGISTER" -eq 0 ]] && CRON_CMD_ARGS+=(--no-register)

  # %q shell-quotes each value so a --dir/--repo containing spaces or shell
  # metacharacters doesn't corrupt the crontab command. Log lives under
  # $HOME, not $INSTALL_DIR - keeps the sparse git checkout itself free of
  # untracked files that `git pull --ff-only` would otherwise have to
  # tolerate on every run.
  QUOTED_ARGS=""
  for a in "${CRON_CMD_ARGS[@]}"; do QUOTED_ARGS+="$(printf '%q ' "$a")"; done
  LOG_FILE="$HOME/.zicer-wiki-hermes-cron.log"
  CRON_LINE="$CRON_MIN $CRON_HOUR * * * $(printf '%q' "$SCRIPT_PATH") ${QUOTED_ARGS}>> $(printf '%q' "$LOG_FILE") 2>&1 $CRON_MARKER"

  # crontab -l exits non-zero with "no crontab for <user>" when none exists
  # yet - not an error, just an empty starting point.
  EXISTING="$(crontab -l 2>/dev/null || true)"
  # Strip any previous zicer-wiki-hermes line by marker (idempotent - never
  # duplicates), then append the current one. `grep -v` exits 1 when every
  # line gets filtered out (e.g. a crontab that only ever had this one
  # entry) - guard with `|| true` so that doesn't trip set -e, same as the
  # `crontab -l` guard above.
  FILTERED="$(printf '%s\n' "$EXISTING" | grep -vF "$CRON_MARKER" || true)"
  { [[ -n "$FILTERED" ]] && printf '%s\n' "$FILTERED"; printf '%s\n' "$CRON_LINE"; } | crontab -
  echo "  OK: daily at $CRON_HOUR:$CRON_MIN -> $SCRIPT_PATH ${CRON_CMD_ARGS[*]}"
  echo "  Log: $LOG_FILE"
  # ponytail: cron log grows unbounded (append-only, no rotation). Fine at
  # one line/day; truncate by hand or switch the redirect to `>` if it ever
  # matters.
fi

if [[ "$DO_REGISTER" -eq 0 ]]; then
  echo "== Done =="
  echo "Installed/updated at: $INSTALL_DIR ($INSTALLED_SIZE on disk)"
  echo "Skipped Hermes registration and restart (--no-register). Re-run without it to register."
  exit 0
fi

echo "== 4. Restart Hermes gateway (pick up new/updated skill content) =="
if [[ "$CHANGED" -eq 0 ]]; then
  echo "  Skipped: nothing changed this run, no need to restart"
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

echo "== 5. Restart Hermes desktop app (pick up new/updated skill content) =="
# Desktop is a plain Electron app (apps/desktop/release/...), not a service -
# `hermes desktop` has no --stop/--restart flag, so detect it by process and
# quit/relaunch by hand. Detection matches the whole desktop tree (main +
# renderer/GPU/network/audio helper processes all live under the same
# apps/desktop/release path), which is a fine enough "is it running" signal
# even though it's broader than just the main process.
if [[ "$CHANGED" -eq 0 ]]; then
  echo "  Skipped: nothing changed this run, no need to restart"
elif ! pgrep -f "hermes-agent/apps/desktop/release" >/dev/null 2>&1; then
  echo "  Skipped: desktop app not running here"
else
  echo "  Desktop app is running - quitting..."
  QUIT_OK=0
  if command -v osascript >/dev/null 2>&1; then
    # Graceful app-level quit (macOS) - lets it save state normally, unlike
    # a bare kill. "Hermes" is the AppleScript-visible name of apps/desktop's
    # Hermes.app bundle.
    osascript -e 'tell application "Hermes" to quit' >/dev/null 2>&1 && QUIT_OK=1
  fi
  if [[ "$QUIT_OK" -eq 0 ]]; then
    # No osascript (Linux) or the graceful quit didn't take - fall back to
    # killing the whole process tree by the same pattern used to detect it.
    pkill -f "hermes-agent/apps/desktop/release" 2>/dev/null || true
  fi
  # Give it a moment to actually exit before relaunching, so we don't race
  # a still-shutting-down instance and end up with two.
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    pgrep -f "hermes-agent/apps/desktop/release" >/dev/null 2>&1 || break
    sleep 1
  done
  if pgrep -f "hermes-agent/apps/desktop/release" >/dev/null 2>&1; then
    echo "  WARNING: desktop app still running after 10s - not relaunching to avoid a duplicate."
    echo "           Close it yourself, then run: hermes desktop --skip-build"
  else
    # --skip-build: relaunch the already-built app instead of a full rebuild.
    nohup hermes desktop --skip-build >/tmp/hermes-desktop-restart.log 2>&1 &
    disown
    echo "  OK: desktop app relaunching (log: /tmp/hermes-desktop-restart.log)"
  fi
fi

echo "== Done =="
echo "Installed/updated at: $INSTALL_DIR ($INSTALLED_SIZE on disk)"
echo "Re-run this script (same command) any time to pull newly added wiki content -"
echo "or let the daily cron job do it automatically."
