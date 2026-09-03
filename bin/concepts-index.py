#!/usr/bin/env python3
"""Компактный индекс концептов: slug + summary, по строке на концепт.

Нужен там, где решение «переиспользовать существующий концепт или завести
новый» (см. CLAUDE.md, «Порог на создание концепта») принимается без доступа
ко всему корпусу — в частности, параллельно работающими агентами.

    python3 bin/concepts-index.py > /path/concepts.tsv
"""
import glob, os, re, sys

def field(text, name):
    m = re.search(r'^%s:\s*(.+)$' % name, text, re.M)
    return m.group(1).strip() if m else ''

rows = []
for path in sorted(glob.glob('wiki/pages/*.md')):
    head = open(path, encoding='utf-8').read(4000)
    if field(head, 'category') != 'Concepts':
        continue
    rows.append((os.path.basename(path)[:-3], field(head, 'summary')))

for slug, summary in rows:
    print('%s\t%s' % (slug, summary))
print('# концептов: %d' % len(rows), file=sys.stderr)
