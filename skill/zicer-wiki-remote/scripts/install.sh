#!/usr/bin/env bash
# Installer for the zicer-wiki-remote Claude skill.
#
# Installs ONE file (SKILL.md) — the wiki data itself is never downloaded, the
# skill fetches it from GitHub over HTTPS at answer time. No git, no clone.
# Run it straight from GitHub with nothing pre-cloned:
#
#   curl -fsSL https://raw.githubusercontent.com/idjugostran/zicer-wiki/master/skill/zicer-wiki-remote/scripts/install.sh | bash
#
# Idempotent — re-running just overwrites the installed SKILL.md with the
# current one (that's also how you update it).
#
# The skill is universal: point it at any repo laid out in the wiki-init /
# wiki-ingest format (wiki/index.md + wiki/pages/*.md) with --repo. Install it
# twice under different --name values to serve two different wikis at once.
#
# Options (env var or flag; flags only work on a local copy, not curl|bash):
#   ZICER_WIKI_REPO   --repo owner/name    wiki repo to read (default: idjugostran/zicer-wiki)
#                     --branch NAME        branch to read (default: master)
#                     --name NAME          installed skill name (default: zicer-wiki-remote)
#                     --description TEXT   skill description (default: the H1 of that wiki's index.md)
#                     --dir PATH           skills dir (default: ~/.claude/skills)
#                     --skill-source URL   where to download SKILL.md from (default: this repo)
#
# claude.ai (web) has no skills directory to write into — there, install by
# uploading the skill/zicer-wiki-remote/ folder through the Skills UI instead.
#
# To uninstall: rm -rf ~/.claude/skills/<name>

set -euo pipefail

REPO="${ZICER_WIKI_REPO:-idjugostran/zicer-wiki}"
BRANCH="master"
SKILL_NAME="zicer-wiki-remote"
DESCRIPTION=""
SKILLS_DIR="$HOME/.claude/skills"
SKILL_SOURCE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --branch) BRANCH="$2"; shift 2 ;;
    --name) SKILL_NAME="$2"; shift 2 ;;
    --description) DESCRIPTION="$2"; shift 2 ;;
    --dir) SKILLS_DIR="$2"; shift 2 ;;
    --skill-source) SKILL_SOURCE="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

BASE_URL="https://raw.githubusercontent.com/$REPO/$BRANCH"
SKILL_SOURCE="${SKILL_SOURCE:-https://raw.githubusercontent.com/idjugostran/zicer-wiki/master/skill/zicer-wiki-remote/SKILL.md}"

# Check the wiki is actually readable BEFORE installing anything - a typo in
# --repo, a wrong branch or a private repo would otherwise install a skill that
# 404s on every question.
echo "== 1. Check wiki is readable =="
INDEX_URL="$BASE_URL/wiki/index.md"
if ! INDEX="$(curl -fsS "$INDEX_URL")"; then
  echo "  ERROR: cannot read $INDEX_URL" >&2
  echo "         Check --repo/--branch, and that the repo is public." >&2
  echo "         (Private repos work at answer time via 'gh api', but this check needs public raw access.)" >&2
  exit 1
fi
echo "  OK: $INDEX_URL ($(printf '%s' "$INDEX" | wc -c | tr -d ' ') bytes)"

# Default description: the index's H1, which wiki-init writes as the wiki's
# domain statement - the closest thing the data has to "what is this wiki about".
if [[ -z "$DESCRIPTION" ]]; then
  DOMAIN="$(printf '%s\n' "$INDEX" | sed -n 's/^# //p' | head -1)"
  # Bash prefix stripping, not sed: the em dash is multibyte and BSD sed
  # mangles it inside a bracket expression.
  DOMAIN="${DOMAIN#Wiki Index — }"; DOMAIN="${DOMAIN#Wiki Index - }"
  [[ -n "$DOMAIN" ]] || { echo "  ERROR: no H1 in index.md - pass --description" >&2; exit 1; }
  DESCRIPTION="Answers questions from the wiki: $DOMAIN"
fi

echo "== 2. Download SKILL.md =="
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
curl -fsS "$SKILL_SOURCE" -o "$TMP"
echo "  OK: $SKILL_SOURCE"

echo "== 3. Patch config (name, description, base URL) =="
# '|' as the sed delimiter: URLs and descriptions contain '/', not '|'. '&' is
# escaped because sed expands it to the whole match in a replacement.
esc() { printf '%s' "$1" | sed 's/[&|]/\\&/g'; }
sed -e "s|^name: .*|name: $(esc "$SKILL_NAME")|" \
    -e "s|^description: .*|description: \"$(esc "$DESCRIPTION")\"|" \
    -e "s|^\*\*Base URL:\*\* .*|**Base URL:** $(esc "$BASE_URL")|" \
    "$TMP" > "$TMP.patched"
mv "$TMP.patched" "$TMP"
grep -q "^\*\*Base URL:\*\* $BASE_URL$" "$TMP" || { echo "  ERROR: base URL patch didn't apply - SKILL.md format changed?" >&2; exit 1; }
echo "  name:        $SKILL_NAME"
echo "  description: $DESCRIPTION"
echo "  base URL:    $BASE_URL"

echo "== 4. Install =="
DEST="$SKILLS_DIR/$SKILL_NAME"
mkdir -p "$DEST"
cp "$TMP" "$DEST/SKILL.md"
echo "  OK: $DEST/SKILL.md"

echo "== Done =="
echo "Restart / start a new Claude session to pick it up."
if [[ "$REPO" != "idjugostran/zicer-wiki" ]]; then
  echo
  echo "NOTE: this SKILL.md is written for the Zicer wiki - its title and its"
  echo "      'When to Use' trigger words say Зицер/Апельсин. For $REPO,"
  echo "      re-run with --name to drop 'zicer' from the name, and edit those:"
  echo "        \$EDITOR $DEST/SKILL.md"
fi
