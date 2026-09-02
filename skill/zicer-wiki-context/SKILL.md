---
name: zicer-wiki-context
description: "Answers Dima Zicer/Apelsin school questions from the wiki."
metadata: {"hermes":{"tags":["dima-zicer","apelsin","parenting","wiki","knowledge-base"],"category":"knowledge-base"}}
---

# Zicer Wiki (Дима Зицер)

Reads the wiki (wiki-init/wiki-ingest format) straight from GitHub over HTTPS —
no clone, no local data, nothing installed but this file.

## Wiki Source

**Base URL:** https://raw.githubusercontent.com/idjugostran/zicer-wiki/master

That line is the only configuration. The wiki always has the same shape under it:

```
<base>/wiki/index.md      — catalog of every page, one line each (committed, always current)
<base>/wiki/overview.md   — synthesis + open questions across sources
<base>/wiki/pages/<slug>.md
```

## When to Use

Trigger whenever **Дима Зицер**, the school **«Апельсин»**, or clearly related
content is mentioned anywhere in the user's message, in any form (not
exhaustive — match the intent, not just these exact strings):

- Russian, any case/declension: `Зицер` / `зицер` (Зицера, Зицеру, Зицером...),
  `Дима Зицер`, `Наташа Зицер`, `Апельсин` / `апельсин` in a school context
  (careful: "апельсин" the fruit is not a trigger — only school/pedagogy
  context), `неформальное образование`
- English: `Zicer`, `Dima Zicer`, `Apelsin school`

A passing mention is enough ("сын сегодня закатил истерику, вспомнила видео
Зицера про это") — it doesn't have to be a question.

This is a **grounding skill**, not a whole-file-attachment one — the wiki is
~25 pages / ~190 KB, so pulling all of it on every mention would be wasteful
and mostly irrelevant. Fetch *just* the pages the index says matter.

## Prerequisites

Network access, plus any one fetch tool (see below). No git, no clone, no
install of the wiki data itself.

## How to Read

Use the first of these that's available in the current environment:

1. **Bash + curl** — exact bytes, no summarization layer:
   `curl -fsS <base>/wiki/index.md`
2. **WebFetch / web_fetch** — where there's no shell (claude.ai). Ask for the
   document's content **verbatim**, not a summary; this skill needs the page
   text, not a paraphrase of it.
3. **Private repo** (no public raw URL): `gh api
   repos/<owner>/<repo>/contents/wiki/index.md -H "Accept: application/vnd.github.raw"`

**Fetch the URL directly — never route through a web-search tool first.**
`raw.githubusercontent.com` serves plain text, not an HTML page, so search
engines essentially never index it — this is true even for a public repo,
and getting zero search results does **not** mean the repo is private or
unreachable. If a direct-fetch tool (`curl`, `WebFetch`/`web_fetch`) is
available, call it on the URL immediately; don't search for the repo or the
URL first and treat empty results as failure.

**If a GitHub app/connector tool is also available, don't use it for this —
go straight to `curl`/`WebFetch`/`web_fetch` instead.** GitHub connector
tools are built around the GitHub API (`api.github.com`) or `github.com`
blob URLs; `raw.githubusercontent.com` is a separate CDN host that such a
tool will typically reject outright with a generic "failed to fetch" and no
useful detail — that failure means the tool doesn't handle this URL, not
that the wiki is unreachable. Don't try the connector first and fall back
after it fails; skip it and fetch the raw URL directly from the start.

Page URLs are never guessed. `wiki/index.md` lists every page as
`[[slug](pages/slug.md)]` — that relative path maps to `<base>/wiki/pages/slug.md`.
A 404 means the index is out of date: say so, don't substitute a
similar-looking page.

## Procedure

1. **Fetch the index.** Get `<base>/wiki/index.md` in full and use it to pick
   the pages actually relevant to the mention/question. Don't answer from
   general parenting/pedagogy knowledge — the wiki is ground truth here, and
   Zicer's specific positions (against grades/homework, against «давать
   сдачи», his particular framing of manipulation) frequently diverge from
   generic advice.

2. **Fetch the relevant pages in full.** For a broad mention with no specific
   question ("что там у Зицера про Апельсин"), start from the entity page
   (`wiki/pages/dima-zicer.md` or `wiki/pages/shkola-apelsin.md`) — dense
   synthesis pages that link out to everything else. For a specific question,
   go straight to the most relevant Concept/Source page(s) from the index.
   Follow one level of `[[slug](pages/slug.md)]` cross-references if they
   point somewhere clearly relevant.

3. **Synthesize an answer grounded in what you fetched, citing in chat-safe
   form:**
   - Cite every claim by naming the page **in prose**, e.g. "по странице вики
     «Родительская функция» ..." or "(вики: Субъектность)" — plain text, no
     brackets. **Never emit the wiki's internal `[[slug](pages/slug.md)]`
     syntax in the reply** — it isn't a link any chat client can render, and
     it can make the whole message fail to parse as Markdown, falling back to
     showing raw `**`/`[...]` literally.
   - Where a footnote in a cited page has a timestamp (`[HH:MM:SS]` or
     `[MM:SS]`) and the underlying Source page's `**Source:**` line has a
     YouTube URL, prefer a clickable timestamp link: convert the timestamp to
     seconds and append it to the URL exactly as the Source page already
     spells it — `[HH:MM:SS](https://www.youtube.com/watch?v=VIDEO_ID&t=SECONDS)`.
     The separator is `&`, not `?`: that URL already carries a query string
     (`?v=`), so a second `?` folds the timestamp into the video id and
     YouTube answers "Video unavailable". Keep the host as written too —
     don't rewrite it to the `youtu.be/ID?t=` short form. That's a real
     absolute URL, so it's safe to emit. Only after actually opening the
     Source page and confirming the video ID — never guess it.
   - Explicitly surface soft tensions between sources rather than picking one
     silently — several pages note related-but-distinct angles on the same
     theme (reward/punishment vs. pseudo-«договор» vs. manipulation are three
     separate critiques of the same underlying pattern), and
     `wiki/overview.md` collects the open questions. If the topic touches one
     of these, mention the related angle instead of flattening it into a
     single claim.
   - If the wiki has no page covering what was asked, say so plainly ("в базе
     знаний вики пока нет ничего про X") instead of quietly falling back to
     general knowledge.
   - **Disclose that this skill answered, with base stats.** `wiki/index.md`
     already carries a `**Sources:** N · **Last updated:** DATE` line right
     after its generated-by comment — you already fetched this in step 1, no
     extra request needed. End the reply with a short plain-text marker on
     its own line built from it, e.g. `📚 Источник: Zicer Wiki
     (zicer-wiki-context) — N видео, обновлено DATE` (fill in the real
     N/DATE from that line) — no brackets or links.

4. **Never write to the wiki from this skill.** This is read-only context
   grounding — if asked to add or change wiki content, say that's outside what
   this skill does rather than attempting it.

## Pitfalls

- **Don't web-search for the repo or the raw URL before fetching it.** Raw
  GitHub content URLs aren't indexed by search engines regardless of repo
  visibility — an empty search result is expected and is not evidence the
  repo is private or down. Call the fetch tool on the URL directly.
- **Don't route the fetch through a GitHub app/connector tool.** It's built
  for `api.github.com`/`github.com`, not the `raw.githubusercontent.com` CDN,
  and will typically fail immediately on this URL. Use `curl`/`WebFetch`/
  `web_fetch` from the start instead of trying the connector first.
- **Don't fetch the whole `wiki/` tree.** Fetch the index, then only what the
  index says is relevant.
- **Don't regenerate `wiki/index.md`.** It's committed, not a runtime
  artifact — whoever edits the wiki regenerates and commits it. Read only.
- **raw.githubusercontent.com is CDN-cached (~5 min).** A commit pushed
  seconds ago may not be visible yet. If the user says a page just changed and
  you don't see it, that's why — wait rather than declaring it missing.
- **Don't put `[[slug](pages/slug.md)]` in the chat reply.** Internal
  cross-reference syntax, meaningless outside the file tree. Cite by page name
  in prose. Real YouTube timestamp links are the one exception.
- **Don't confuse «Апельсин» the school with the fruit.** Only treat it as a
  trigger when the context is clearly the school/pedagogy, not produce or
  color.

## Verification

After answering, every factual claim should be traceable to a named wiki page
(in prose, not a `[[slug](pages/slug.md)]` link). If it isn't, it was answered
from general knowledge — go back and ground it, or say the wiki doesn't cover
it. Check the reply contains no literal `[[...]]` or `pages/....md` text, and
that it ends with the `📚 Источник: Zicer Wiki (zicer-wiki-context) — N видео,
обновлено DATE` disclosure line, with real numbers from `wiki/index.md`'s
stats line — not literal "N"/"DATE" placeholders.
