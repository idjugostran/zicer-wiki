#!/bin/bash
# Печатает ID следующего необработанного видео канала (или ничего, если очередь пуста).
# Очередь кэшируется в config/queue.txt (популярность ↓), обновить: rm config/queue.txt
set -euo pipefail
cd "$(dirname "$0")/.."
Q=config/queue.txt
[ -s "$Q" ] || yt-dlp --flat-playlist --print id \
  "https://www.youtube.com/channel/UCUYqSjRbCrCHqWUNvOHJwRA/videos" > "$Q"
{ grep -rhoE 'youtu(be\.com/watch\?v=|\.be/)[A-Za-z0-9_-]{11}' wiki/pages | sed -E 's/.*(v=|be\/)//'
  cat config/skip.txt 2>/dev/null; } | sort -u > /tmp/zicer-done.$$
grep -vxF -f /tmp/zicer-done.$$ "$Q" | head -1
rm -f /tmp/zicer-done.$$
