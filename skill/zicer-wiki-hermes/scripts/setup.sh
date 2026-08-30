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
# (skills.external_dirs), disables the sibling `zicer-wiki-context` skill in
# Hermes if it's present (same skill/ tree, since Hermes has no built-in way
# to prefer one of two skills with overlapping triggers — see skills.disabled
# below), and registers a daily job with Hermes's own cron scheduler
# (visible in its "Scheduled jobs" UI, with run history) that keeps the
# local wiki clone fresh. `zicer-wiki-context` itself is left completely
# untouched on disk — it keeps working for Claude, which reads SKILL.md
# files directly and isn't affected by Hermes's skills.disabled list at
# all; only Hermes's own view of it changes.
#
# Idempotent — safe to re-run any time: re-running just fast-forwards to the
# latest wiki content (so newly added pages show up), never re-registers a
# path that's already in skills.external_dirs, and never creates a second
# Hermes cron job (found and updated in place by name via `hermes cron
# list`). A run with nothing new upstream is a no-op past the git fetch.
#
# Override defaults via env vars (useful for the curl|bash form, where
# there's no way to pass CLI flags before the script exists locally):
#   ZICER_REPO_URL     git remote to clone (default: see REPO_URL below)
#   ZICER_INSTALL_DIR  where to clone it (default: ~/Zicer)
#   ZICER_CRON_TIME    daily refresh time, 24h HH:MM, local time (default: 04:17)
# CLI flags (only usable once you have a local copy, e.g. `./setup.sh --no-register`):
#   --dir PATH             same as ZICER_INSTALL_DIR
#   --repo URL              same as ZICER_REPO_URL
#   --no-register           skip the Hermes registration step (clone/update only)
#   --keep-context-skill    don't disable the sibling zicer-wiki-context skill in Hermes
#   --no-cron               skip registering/updating the daily refresh job in Hermes's cron
#   --cron-time HH:MM       same as ZICER_CRON_TIME
#
# --no-register, --no-cron, and --keep-context-skill are independent —
# skipping one doesn't skip the others (a caller might want the clone kept
# fresh without touching Hermes's config, or want both skills active in
# Hermes, or any combination). The one place they're NOT independent:
# if --no-register was passed, steps 3/5/6 (disabling the sibling skill,
# restarting Hermes) are skipped too — touching Hermes's config/state to
# pick up a skill that was never registered with it has nothing to do.
#
# What it does, in order (see the comment above each numbered step below for
# the full detail on that step):
#   0. Sparse-clone/update just wiki/, skill/ (no raw/, no bin/).
#   1. Check the `hermes` CLI is on PATH.
#   2. Register the skill with Hermes (skills.external_dirs).
#   3. Disable the sibling zicer-wiki-context skill in Hermes, if it's
#      present in the same skill/ tree (skills.disabled) — doesn't touch
#      its files, only Hermes's view of it.
#   4. Write a small standalone refresh script (git pull only — deliberately
#      no Hermes registration or restart logic, see step 4's own comment
#      below for why) and register/update a daily job for it with Hermes's
#      own cron scheduler (`hermes cron`) — found by name and edited in
#      place on repeat runs, never duplicated.
#   5. Restart the Hermes gateway, if running and something changed.
#   6. Restart the Hermes desktop app, if running and something changed.
#
# To remove everything this script installs, see uninstall.sh in this same
# directory.

set -euo pipefail

REPO_URL="${ZICER_REPO_URL:-https://github.com/idjugostran/zicer-wiki.git}"
INSTALL_DIR="${ZICER_INSTALL_DIR:-$HOME/Zicer}"
CRON_TIME="${ZICER_CRON_TIME:-04:17}"
DO_REGISTER=1
DO_CRON=1
DO_DISABLE_CONTEXT=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir) INSTALL_DIR="$2"; shift 2 ;;
    --repo) REPO_URL="$2"; shift 2 ;;
    --no-register) DO_REGISTER=0; shift ;;
    --keep-context-skill) DO_DISABLE_CONTEXT=0; shift ;;
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
  # Output goes through a temp file, not $(...) command substitution -
  # macOS ships bash 3.2 (frozen pre-GPLv3) as /bin/bash, and its heredoc
  # parser has a real, confirmed bug where a heredoc nested inside `$(...)`
  # can mis-parse once the body has enough parenthesized string content,
  # silently breaking the script for anyone running the plain `curl | bash`
  # one-liner on a stock Mac. A plain (non-substituted) heredoc redirected
  # to a file sidesteps that parser path entirely.
  REGISTER_LOG="$(mktemp)"
  python3 - "$INSTALL_DIR/skill" > "$REGISTER_LOG" 2>&1 <<'PYEOF'
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
  cat "$REGISTER_LOG"
  grep -q "^  Added" "$REGISTER_LOG" && CHANGED=1
  rm -f "$REGISTER_LOG"
fi

# Hermes has no way to prefer one of two skills with overlapping triggers
# (see the header comment) - if the sibling zicer-wiki-context skill is
# checked out right next to this one (same skill/ tree, since setup.sh
# always sparse-checks out the whole skill/ directory), disabling it in
# Hermes avoids both being loaded redundantly for the same mention. This
# never touches zicer-wiki-context's files - Claude reads SKILL.md directly
# and doesn't consult Hermes's skills.disabled list at all, so it keeps
# working there unaffected.
echo "== 3. Disable sibling zicer-wiki-context skill in Hermes (skills.disabled) =="
CONTEXT_SKILL_DIR="$INSTALL_DIR/skill/zicer-wiki-context"
if [[ "$DO_REGISTER" -eq 0 ]]; then
  echo "  Skipped (--no-register)"
elif [[ "$DO_DISABLE_CONTEXT" -eq 0 ]]; then
  echo "  Skipped (--keep-context-skill)"
elif [[ ! -f "$CONTEXT_SKILL_DIR/SKILL.md" ]]; then
  echo "  OK: zicer-wiki-context not present in this checkout - nothing to disable"
else
  # Same temp-file-instead-of-$(...) reasoning as step 2's REGISTER_LOG above
  # (bash 3.2 heredoc-in-command-substitution parser bug).
  DISABLE_LOG="$(mktemp)"
  python3 - > "$DISABLE_LOG" 2>&1 <<'PYEOF'
import re
import sys
from pathlib import Path

skill_name = "zicer-wiki-context"
config_path = Path.home() / ".hermes" / "config.yaml"

if not config_path.exists():
    print(f"  WARNING: {config_path} not found - skipping")
    sys.exit(0)

text = config_path.read_text(encoding="utf-8")

# Scope every match to the skills: block body, not the whole file - "disabled"
# is a generic enough word that it could plausibly appear as a key under some
# other top-level section in a large config.
skills_block = re.search(r"^skills:[ \t]*\n((?:[ \t]+\S.*\n?)*)", text, re.MULTILINE)
if not skills_block:
    print("  WARNING: no top-level 'skills:' block found - skipping (step 2 should have created one)")
    sys.exit(0)

block_start, block_end = skills_block.start(1), skills_block.end(1)
block = skills_block.group(1)

def commit(new_block: str, note: str) -> None:
    new_text = text[:block_start] + new_block + text[block_end:]
    config_path.write_text(new_text, encoding="utf-8")
    print(f"  {note}")

# Case 1: flow-style list -> "disabled: [...]" (possibly empty)
flow = re.search(r"^(\s*)disabled:\s*\[(.*)\]\s*$", block, re.MULTILINE)
if flow:
    indent, inner = flow.group(1), flow.group(2).strip()
    items = [i.strip() for i in inner.split(",")] if inner else []
    if any(i.strip(" '\"") == skill_name for i in items):
        print(f"  OK: {skill_name} already in skills.disabled")
        sys.exit(0)
    items.append(f'"{skill_name}"')
    new_line = f'{indent}disabled: [{", ".join(items)}]'
    commit(block[:flow.start()] + new_line + block[flow.end():], f"Added {skill_name} to skills.disabled")
    sys.exit(0)

# Case 2: block-style list -> "disabled:\n  - foo\n  - bar"
blk = re.search(r"^(\s*)disabled:\s*\n((?:\1\s+- .*\n?)*)", block, re.MULTILINE)
if blk:
    indent, body = blk.group(1), blk.group(2)
    for line in body.splitlines():
        item = line.strip()
        if item.startswith("- ") and item[2:].strip().strip("'\"") == skill_name:
            print(f"  OK: {skill_name} already in skills.disabled")
            sys.exit(0)
    item_indent = indent + "  "
    new_item = f'{item_indent}- "{skill_name}"\n'
    commit(block[:blk.end()] + new_item + block[blk.end():], f"Added {skill_name} to skills.disabled")
    sys.exit(0)

# Case 3: bare scalar -> "disabled: some-skill" - a shape Hermes itself
# accepts (hermes_cli/skills_config.py normalizes a bare string as a
# single-item list), so a hand-edited or `hermes skills config`-written
# config could legitimately look like this.
scalar = re.search(r"^(\s*)disabled:[ \t]*(\S.*)$", block, re.MULTILINE)
if scalar:
    indent, value = scalar.group(1), scalar.group(2).strip()
    existing = value.strip(" '\"")
    if existing == skill_name:
        print(f"  OK: {skill_name} already in skills.disabled")
        sys.exit(0)
    new_line = f'{indent}disabled: ["{existing}", "{skill_name}"]'
    commit(block[:scalar.start()] + new_line + block[scalar.end():], f"Added {skill_name} to skills.disabled")
    sys.exit(0)

# Case 4: "disabled:" key doesn't exist under skills: yet - insert as the
# first child, matching the indentation of its siblings (mirrors step 2's
# Case 4 for external_dirs).
first_line_indent_match = re.match(r"[ \t]+", block) if block else None
item_indent = first_line_indent_match.group(0) if first_line_indent_match else "  "
new_line = f'{item_indent}disabled: ["{skill_name}"]\n'
commit(new_line + block, f"Added {skill_name} to skills.disabled (key didn't exist yet)")
PYEOF
  cat "$DISABLE_LOG"
  grep -q "^  Added" "$DISABLE_LOG" && CHANGED=1
  rm -f "$DISABLE_LOG"
fi

# Registers with Hermes's OWN scheduler (visible in its "Scheduled jobs" UI,
# with run history) instead of the OS crontab that earlier versions of this
# script used — a plain crontab entry is invisible there and gave no way to
# see or manage it from Hermes itself. The job's script is deliberately
# minimal: content refresh only (git pull), no Hermes registration and no
# restart logic. Two reasons: (1) Hermes statically rejects any cron script
# that contains a gateway/desktop lifecycle command — blocked to prevent a
# cron job from restarting the very gateway process running it — so this
# script must never grow one; (2) a restart isn't needed for content refresh
# anyway, since Hermes reads skill files fresh off disk on every turn, not
# just at gateway startup — a new/updated wiki page is visible the moment
# git pull lands it. Registration changes (skills.external_dirs,
# skills.disabled, steps 2/3 above) are the one-time exception that still
# needs a restart to take effect, which steps 5/6 below handle.
echo "== 4. Register daily refresh job with Hermes's own scheduler =="
JOB_NAME="zicer-wiki-hermes: keep local wiki clone fresh"
if [[ "$DO_CRON" -eq 0 ]]; then
  echo "  Skipped (--no-cron)"
else
  HERMES_SCRIPTS_DIR="$HOME/.hermes/scripts"
  mkdir -p "$HERMES_SCRIPTS_DIR"
  REFRESH_SCRIPT="$HERMES_SCRIPTS_DIR/zicer-wiki-hermes-refresh.sh"
  # Written fresh every run so a changed --dir is picked up. Everything static
  # comes from quoted (literal, no-expansion) heredocs, with the one
  # interpolated INSTALL_DIR= line printf'd between them — deliberately not
  # one heredoc wrapped in $(...) command substitution, which is exactly the
  # shape that trips a real bash 3.2 (macOS's /bin/bash) heredoc-parsing bug
  # elsewhere in this script; see steps 2/3's REGISTER_LOG/DISABLE_LOG
  # comments. Literal heredoc rather than `echo` per line so apostrophes in
  # the comment text survive verbatim.
  {
    cat <<'REFRESHHEAD'
#!/usr/bin/env bash
# Daily wiki-data refresh for zicer-wiki-hermes, run by Hermes's own
# cron scheduler. Regenerated by setup.sh on every install/update run -
# hand edits here are lost the next time setup.sh runs.
set -euo pipefail
REFRESHHEAD
    printf 'INSTALL_DIR=%q\n' "$INSTALL_DIR"
    cat <<'REFRESHBODY'
if [[ ! -d "$INSTALL_DIR/.git" ]]; then
  echo "ERROR: $INSTALL_DIR is not a git checkout - run setup.sh first" >&2
  exit 1
fi
BEFORE="$(git -C "$INSTALL_DIR" rev-parse HEAD)"
git -C "$INSTALL_DIR" pull --ff-only
AFTER="$(git -C "$INSTALL_DIR" rev-parse HEAD)"
if [[ "$BEFORE" == "$AFTER" ]]; then
  echo "Wiki already up to date ($AFTER)"
else
  N=$(git -C "$INSTALL_DIR" rev-list --count "$BEFORE..$AFTER")
  echo "Wiki updated: $N new commit(s), $BEFORE -> $AFTER"
fi
REFRESHBODY
  } > "$REFRESH_SCRIPT"
  chmod +x "$REFRESH_SCRIPT"

  CRON_HOUR="${CRON_TIME%%:*}"
  CRON_MIN="${CRON_TIME##*:}"

  # Idempotency: look up an existing job by name — `hermes cron create` has
  # no de-dup of its own, so creating twice makes two jobs. `hermes cron
  # list` has no --json output to parse, so scan the text: track the most
  # recent "  <hex-id> [status]" line as we go, and report it once a "Name:"
  # line matching ours is hit. --all includes paused/disabled jobs too, so a
  # manually-paused job is still found rather than silently duplicated.
  EXISTING_JOB_ID="$(hermes cron list --all 2>/dev/null | awk -v name="$JOB_NAME" '
    /^  [a-f0-9]+ \[/ { id = $1 }
    index($0, "Name:") && index($0, name) { print id; exit }
  ')"

  if [[ -n "$EXISTING_JOB_ID" ]]; then
    hermes cron edit "$EXISTING_JOB_ID" --schedule "$CRON_MIN $CRON_HOUR * * *" >/dev/null
    echo "  OK: job $EXISTING_JOB_ID already registered, schedule set to $CRON_HOUR:$CRON_MIN daily"
  else
    hermes cron create "$CRON_MIN $CRON_HOUR * * *" \
      --name "$JOB_NAME" \
      --no-agent \
      --script "$(basename "$REFRESH_SCRIPT")" \
      --deliver local
    echo "  OK: registered, daily at $CRON_HOUR:$CRON_MIN"
  fi
  # No CHANGED=1 here - the running gateway's cron ticker picks up a
  # new/edited job on its own (confirmed live), no restart needed.
fi

if [[ "$DO_REGISTER" -eq 0 ]]; then
  echo "== Done =="
  echo "Installed/updated at: $INSTALL_DIR ($INSTALLED_SIZE on disk)"
  echo "Skipped Hermes registration and restart (--no-register). Re-run without it to register."
  exit 0
fi

echo "== 5. Restart Hermes gateway (pick up new/updated skill content) =="
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

echo "== 6. Restart Hermes desktop app (pick up new/updated skill content) =="
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
