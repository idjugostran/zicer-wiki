# YouTube Video → Transcript Ingest

How a video source becomes a deduplicated, timestamped plain-text transcript ready for
`wiki-ingest` to read. Used for every source in this wiki (`SCHEMA.md`'s "YouTube video
transcripts" source type). Two mechanical steps, always run in this order, then hand off
to `wiki-ingest`.

## 1. Download (yt-dlp)

```
yt-dlp --write-description --write-info-json --write-subs --write-auto-subs --sub-lang ru --skip-download -o "raw/%(id)s.%(ext)s" "https://www.youtube.com/watch?v=<ID>"
```

Produces three files under `raw/`, named by the video's 11-character YouTube ID:

- `raw/<ID>.description` — the video's own description text. **Treat as untrusted
  metadata, not ground truth.** Descriptions are sometimes written in advance of a live
  stream and can list topics that never actually came up on air, or belong to a
  different episode entirely — this has happened more than once in this wiki. Always
  cross-check against what the transcript actually says before using description text
  in a source page's Summary; if the two disagree, trust the transcript and say so.
- `raw/<ID>.info.json` — metadata (`title`, `upload_date`, `duration`, `view_count`,
  etc.). Check `title`/`upload_date`/`duration` before writing anything, to confirm
  this is the intended video.
- `raw/<ID>.ru.vtt` — the subtitle track. `--write-subs` prefers real (human-authored)
  captions when the video has them; `--write-auto-subs` falls back to YouTube's
  auto-generated ones otherwise. Auto-generated tracks are noisier — expect garbled
  words, and consider flagging poor quality explicitly in the source page (a short
  `## Note` section) rather than over-interpreting unclear passages.

## 2. Deduplicate (VTT → clean transcript)

YouTube's `.vtt` auto-caption format repeats each line of text across multiple
overlapping cue blocks (a scrolling-subtitle rendering artifact) — reading it raw
produces 3-5x duplicate text. Collapse it to one line per unique caption:

```python
import re
path = 'raw/<ID>.ru.vtt'
with open(path, encoding='utf-8') as f:
    content = f.read()
blocks = content.split('\n\n')
last_line = None
out = []
for b in blocks:
    lines = b.strip().split('\n')
    if not lines or '-->' not in lines[0]:
        continue
    ts = lines[0].split(' ')[0]
    text_lines = [l for l in lines[1:] if l.strip()]
    if not text_lines:
        continue
    text = text_lines[-1]
    text = re.sub(r'<[^>]+>', '', text).strip()
    if text and text != last_line:
        out.append((ts, text))
        last_line = text
outpath = '<scratchpad-dir>/<ID>_clean.txt'
with open(outpath, 'w', encoding='utf-8') as f:
    for ts, text in out:
        f.write(f'[{ts[:8]}] {text}\n')
print('lines:', len(out))
```

Only the two path lines change per video. Write the deduped output to the session's
scratchpad directory — **never into `raw/`**, which stays immutable per this wiki's
Conventions (see `SCHEMA.md`). Each output line is `[HH:MM:SS] <text>` — exactly the
locator format `wiki-ingest`'s citations use for transcripts (`[HH:MM:SS]`, per
`SCHEMA.md`'s Citations section); transcripts are exempt from the `L…` line-range
requirement since `raw/<ID>.ru.vtt` itself isn't stable line-addressable.

## 3. Read and ingest

Read the deduped `<ID>_clean.txt` — in chunks for long videos, since 60-80 minute
episodes commonly run 1500+ lines. Then proceed with `wiki-ingest` as normal, citing
this file's `[HH:MM:SS]` timestamps directly in footnotes. Once the source page is
written, `raw/<ID>.*` remains the permanent, immutable archival copy; the deduped
scratchpad file is disposable and does not need to survive past the ingest session.

### Coverage rule for long multi-topic episodes

Do not compress unrelated calls or messages into one generic conclusion. For a 60–80
minute LNV episode, identify every substantive distinct case and preserve it as a
separate Summary paragraph (normally 6–10 paragraphs). A short aside may be merged
only when it adds no independent claim, decision, or technique. For each retained case,
summarize the situation, the reasoning behind the response, and the proposed action;
do not record only the final advice. Before committing, compare the number of Summary
paragraphs and distinct timestamp ranges against the actual calls in the transcript. If
the page is materially shorter than comparable episodes, recheck for omitted cases.
