#!/usr/bin/env python3
"""Проставляет обратную ссылку на странице и обновляет её frontmatter.

Шаг 7 скилла wiki-ingest (backlink audit) правит десятки страниц за ингест.
Руками это ошибкоопасно: у Concept/Entity-страниц есть секции «## Appearances in
Sources» и «## Related Concepts», а у Source-страниц их нет — там связь дописывается
в «## Relation to Other Wiki Pages» отдельным предложением. Скрипт сам выбирает
нужную форму по структуре страницы.

  # в Concept/Entity: пункт в Appearances in Sources
  python3 bin/patch-backlinks.py <slug> app "- [[src](pages/src.md)] — заметка" --src src

  # в Concept/Entity: пункт в Related Concepts
  python3 bin/patch-backlinks.py <slug> rel "- [[c](pages/c.md)] — как связано"

  # в Source: предложение в Relation to Other Wiki Pages (секция выбирается сама,
  # если у страницы нет Appearances/Related — режим можно не указывать)
  python3 bin/patch-backlinks.py <slug> rel "Текст предложения." --src src

--src <slug> добавляет источник в frontmatter `sources:`, если его там ещё нет.
`updated:` проставляется сегодняшней датой в любом случае.
"""
import argparse
import datetime
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PAGES = os.path.join(ROOT, 'wiki', 'pages')
HEADS = {'app': '## Appearances in Sources', 'rel': '## Related Concepts'}
RELATION = '## Relation to Other Wiki Pages'


def bump_frontmatter(fm, src, today):
    if src:
        m = re.search(r'^sources: \[(.*?)\]', fm, re.M)
        if m and src not in [x.strip() for x in m.group(1).split(',')]:
            joined = (m.group(1) + ', ' + src) if m.group(1).strip() else src
            fm = fm[:m.start()] + 'sources: [%s]' % joined + fm[m.end():]
    if re.search(r'^updated: ', fm, re.M):
        fm = re.sub(r'^updated: .*$', 'updated: ' + today, fm, count=1, flags=re.M)
    return fm


def append_to_section(body, head, text):
    i = body.index(head)
    j = body.find('\n## ', i)
    if j == -1:
        j = len(body)
    seg = body[i:j].rstrip('\n')
    joiner = ' ' if head == RELATION else '\n'
    return body[:i] + seg + joiner + text.strip() + '\n\n' + body[j:].lstrip('\n')


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('slug')
    ap.add_argument('mode', choices=['app', 'rel'], nargs='?', default='rel')
    ap.add_argument('text')
    ap.add_argument('--src', default=None)
    ap.add_argument('--date', default=datetime.date.today().isoformat())
    args = ap.parse_args()

    path = os.path.join(PAGES, args.slug + '.md')
    if not os.path.exists(path):
        sys.exit('нет такой страницы: %s' % path)
    raw = open(path, encoding='utf-8').read()
    if not raw.startswith('---\n'):
        sys.exit('%s: нет frontmatter' % args.slug)
    _, fm, body = raw.split('---\n', 2)

    head = HEADS[args.mode]
    if head not in body:
        if RELATION not in body:
            sys.exit('%s: нет ни "%s", ни "%s"' % (args.slug, head, RELATION))
        head = RELATION

    body = append_to_section(body, head, args.text)
    fm = bump_frontmatter(fm, args.src, args.date)
    open(path, 'w', encoding='utf-8').write(('---\n' + fm + '---\n' + body).rstrip('\n') + '\n')
    print('ok %s -> %s' % (args.slug, head))


if __name__ == '__main__':
    main()
