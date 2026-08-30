---
name: zicer-wiki-hermes
description: "Answers Dima Zicer/Apelsin school questions from a locally-cloned copy of the wiki, kept fresh by a daily cron job (Hermes-only — see the sibling zicer-wiki-context skill for the remote-fetch/Claude variant)."
metadata: {"hermes":{"tags":["dima-zicer","apelsin","parenting","wiki","knowledge-base","local-clone"],"category":"knowledge-base"}}
---

# Zicer Wiki (Дима Зицер) Context

## When to Use

Trigger whenever **Дима Зицер**, the school **«Апельсин»**, or clearly
related content is mentioned anywhere in the user's message, in any of these
forms (not exhaustive — match the intent, not just these exact strings):

- Russian, any case/declension: `Зицер` / `зицер` (Зицера, Зицеру, Зицером...),
  `Дима Зицер`, `Наташа Зицер`, `Апельсин` / `апельсин` in a school context
  (careful: "апельсин" the fruit is not a trigger — only school/pedagogy
  context), `неформальное образование`
- English: `Zicer`, `Dima Zicer`, `Apelsin school`

Not limited to explicit questions ("что говорит Зицер про истерики") — any
passing mention is enough ("сын сегодня закатил истерику, вспомнила видео
Зицера про это").

This is a **grounding skill**, not a whole-file-attachment one — read *just*
the pages relevant to the question, not the whole wiki.

## Prerequisites

None — pure file reads, no tools or installs beyond what an install of this
skill already provides.

This skill is portable — it has **no hard-coded machine path or username**.
Every install (this one, or a fresh one on someone else's machine) puts a
full copy of the wiki data next to the skill itself, always in the exact
same relative shape:

```
<wiki-root>/
├── wiki/
│   ├── index.md     (committed — catalog of every page, one line each)
│   ├── overview.md
│   └── pages/*.md
└── skill/zicer-wiki-hermes/SKILL.md   <- this file
```

So **`<wiki-root>` is always exactly two directories above this file's own
location.** Resolve it from wherever this skill was loaded from — do not
assume any particular home directory or username; the install path varies
per machine (default `~/Zicer`, but whoever ran the installer may have
pointed `--dir` somewhere else entirely).

## How to Run

No command to invoke — just `read_file` the relevant files under
`<wiki-root>/wiki/`. Start with `wiki/index.md` (always present and current;
it's committed to the repo, not generated on demand) to decide which pages
are relevant, then `read_file` those specific pages.

## Quick Reference

- Index: `wiki/index.md` — grouped by category (Sources / Entities /
  Concepts), one-line summary per page
- Entity hubs (start here for broad/no-specific-question mentions):
  `wiki/pages/dima-zicer.md`, `wiki/pages/shkola-apelsin.md`
- Synthesis + open questions: `wiki/overview.md`
- Internal wiki links look like `[[slug](pages/slug.md)]` — that's the
  wiki's own file-navigation syntax for following cross-references *while
  reading pages*. Never put that syntax in the chat reply itself (see
  Pitfalls) — cite pages in prose instead.

## Procedure

1. **Read the index.** `read_file` on `wiki/index.md` in full. Use it to
   identify which pages are actually relevant to the mention/question.
   Don't answer from general parenting/pedagogy knowledge — the wiki is
   ground truth here, and Zicer's specific positions (e.g. against
   grades/homework, against "давать сдачи", his particular framing of
   manipulation) frequently diverge from generic advice.

2. **Read the relevant pages in full** with `read_file`, not summaries or
   greps. For a broad mention with no specific question ("что там у Зицера
   про Апельсин"), start from the entity page (`wiki/pages/dima-zicer.md` or
   `wiki/pages/shkola-apelsin.md`) — both link out to everything else. For a
   specific question, go straight to the most relevant Concept/Source
   page(s) from the index. Follow one level of `[[slug](pages/slug.md)]`
   cross-references if they point somewhere clearly relevant.

3. **Synthesize an answer grounded in what you read, citing in chat-safe
   form:**
   - Cite every claim by naming the page **in prose**, e.g. "по странице
     вики «Родительская функция» ..." or "(вики: Субъектность)" — plain
     text, no brackets. **Never emit the wiki's internal
     `[[slug](pages/slug.md)]` link syntax in the reply** — `pages/slug.md`
     is a relative path with no meaning outside this file tree, and the
     double-bracket form isn't a link a chat client can render at all.
     Worse, it can make the whole message fail to parse as Markdown and
     fall back to showing raw `**`/`[...]` syntax literally — see Pitfalls.
   - Where a footnote in the cited page has a timestamp (`[HH:MM:SS]`) and
     the underlying Source page's `**Source:**` line has a YouTube URL,
     prefer rendering that as a clickable timestamp link instead of a bare
     citation: convert the timestamp to seconds and link as
     `[HH:MM:SS](https://youtu.be/VIDEO_ID?t=SECONDS)`. This *is* a real,
     absolute, valid link (unlike the internal wiki syntax above), so it's
     safe to emit. Only do this after actually opening the Source page and
     confirming the video ID — never guess it.
   - Explicitly surface soft tensions between sources rather than picking
     one silently — several pages note related-but-distinct angles on the
     same theme (e.g. reward/punishment vs. pseudo-«договор» vs.
     manipulation are three separate critiques of the same underlying
     pattern). If the topic touches one of these, mention the related
     angle instead of flattening it into a single claim.
   - If the wiki has no page covering what was asked, say so plainly
     ("в базе знаний вики пока нет ничего про X") instead of silently
     falling back to general knowledge.
   - **Disclose that this skill answered.** End the reply with a short,
     plain-text marker on its own line: `📚 Источник: Zicer Wiki
     (zicer-wiki-hermes)` — no brackets/links, just text, so it can't trip
     the same Markdown-parsing issue as citations above.

4. **Never write to the wiki from this skill.** This is read-only context
   grounding — if asked to add or change wiki content, say that's outside
   what this skill does rather than attempting it.

## Pitfalls

- **Don't hard-code `<wiki-root>`.** Always resolve it relative to this
  file's own location — an absolute path baked in breaks on every other
  install.
- **Don't regenerate `wiki/index.md`.** It's committed, not a runtime
  artifact — whoever edits the wiki regenerates and commits it as part of
  that change. This skill only ever reads it.
- **Don't put `[[slug](pages/slug.md)]` in the chat reply.** That's the
  wiki's internal cross-reference syntax, meaningless (and potentially
  Markdown-parse-breaking) outside the file tree. Cite pages by name in
  prose instead. Real YouTube-timestamp links are the one exception — those
  are genuine absolute URLs, safe to emit as-is.
- **Don't confuse «Апельсин» the school with the fruit.** Only treat it as
  a trigger when the context is clearly the school/pedagogy, not produce or
  color.

## Verification

After answering, every factual claim in the response should be traceable to
a named wiki page (in prose, not a `[[slug](pages/slug.md)]` link). If it
isn't, something was answered from general knowledge instead of the wiki —
go back and ground it, or say the wiki doesn't cover it. Also check the
reply doesn't contain any literal `[[...]]` or `pages/....md` text — that
means the internal link syntax leaked into the chat-facing answer. Finally,
confirm the reply ends with the `📚 Источник: Zicer Wiki
(zicer-wiki-hermes)` disclosure line — if it's missing, add it before
sending.
