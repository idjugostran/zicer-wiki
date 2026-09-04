#!/usr/bin/env python3
"""Проверяет дословность цитат в «ёлочках» против сырых субтитров.

Для каждой Source-страницы с ютуб-транскриптом берёт raw/<ID>.ru.vtt, схлопывает
его тем же способом, что config/youtube-transcript.md, и сверяет каждую цитату из
секции ## Footnotes.

Concept-страницы проверяются тоже, но только те цитаты, что помечены локатором:
    «дословная цитата» [00:12:34]
Без локатора цитата не проверяется — в теле концептов кавычки несут две разные
функции, обрамляя то настоящую цитату, то термин или пересказ («вторая натура»,
«взрослый прав по умолчанию»), и различить их машинно нельзя. Локатор и есть
признак, которым автор заявляет: это дословно. Источники берутся из frontmatter
`sources:`, дорожки склеиваются. Frontmatter не сканируется.

Что считается допустимым (и потому не сообщается):
  пунктуация и регистр; «ё»; числительные словами вместо цифр; склейка слов,
  которые распознавание разорвало; редакторские вставки в квадратных скобках;
  пропуск внутри цитаты, помеченный многоточием.
Что сообщается как нарушение:
  замена слова, изменение порядка слов, реконструкция неразборчивого места.

Использование:
  python3 bin/audit-quotes.py            # отчёт по всем страницам
  python3 bin/audit-quotes.py <slug>...  # только по указанным
  python3 bin/audit-quotes.py --strict   # ненулевой код возврата при нарушениях
"""
import difflib
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PAGES = os.path.join(ROOT, 'wiki', 'pages')
RAW = os.path.join(ROOT, 'raw')

VID = re.compile(r'watch\?v=([\w-]{11})')
SOURCES = re.compile(r'^sources:\s*\[(.*?)\]', re.M | re.S)
# Цитата в Concept-странице проверяется, только если помечена локатором.
CITED = re.compile(r'«([^»]{12,300})»(?=[^«»]{0,60}\[\d\d:\d\d:\d\d\])')
CATEGORY = re.compile(r'^category:\s*(\w+)', re.M)
QUOTE = re.compile(r'«([^»]{12,300})»')
CUE = re.compile(r'^(\d\d:\d\d:\d\d)\.\d\d\d -->')
TAG = re.compile(r'<[^>]+>')
BRACKET = re.compile(r'\[[^\]]*\]')

# Числительные словами: в дорожке они стоят цифрами, в цитате раскрыты словом.
NUMERALS = {
    'один', 'одна', 'одно', 'двое', 'трое', 'двух', 'трёх', 'трех', 'четырёх',
    'четырех', 'пяти', 'шести', 'семи', 'восьми', 'девяти', 'десяти', 'один',
    'два', 'три', 'четыре', 'пять', 'шесть', 'семь', 'восемь', 'девять',
    'десять', 'одиннадцать', 'двенадцать', 'тринадцать', 'четырнадцать',
    'пятнадцать', 'шестнадцать', 'семнадцать', 'восемнадцать', 'девятнадцать',
    'двадцать', 'тридцать', 'сорок', 'пятьдесят', 'шестьдесят', 'семьдесят',
    'восемьдесят', 'девяносто', 'сто', 'ста', 'двести', 'триста', 'четыреста',
    'пятьсот', 'шестьсот', 'семьсот', 'восемьсот', 'девятьсот', 'тысяча',
    'тысячи', 'тысячу', 'тысячей', 'половиной', 'половина', 'процентов',
    'процента', 'процент', 'рублей', 'рубля', 'года', 'лет', 'году',
}


def dedupe_vtt(path):
    """VTT -> текст без таймкодов, тем же способом, что config/youtube-transcript.md."""
    with open(path, encoding='utf-8') as fh:
        blocks = fh.read().split('\n\n')
    out, last = [], None
    for b in blocks:
        lines = b.strip().split('\n')
        if not lines or '-->' not in lines[0]:
            continue
        texts = [l for l in lines[1:] if l.strip()]
        if not texts:
            continue
        text = TAG.sub('', texts[-1]).strip()
        if text and text != last:
            out.append(text)
            last = text
    return ' '.join(out)


# Составные числительные-прилагательные: в дорожке «13-летнему», в цитате
# «тринадцатилетнему». Цифра при нормализации отпадает, остаётся «летнему»,
# поэтому у слова из цитаты срезается числительная приставка.
AGE = re.compile(r'^(?:одно|двух|трёх|трех|четырёх|четырех|пяти|шести|семи|восьми|'
                 r'девяти|десяти|одиннадцати|двенадцати|тринадцати|четырнадцати|'
                 r'пятнадцати|шестнадцати|семнадцати|восемнадцати|девятнадцати|'
                 r'двадцати|тридцати|сорока|пятидесяти)(лет\w*)$')


def strip_age(word):
    m = AGE.match(word)
    return m.group(1) if m else word


def stems(text):
    """Основы значимых слов; числительные и короткие слова отбрасываются."""
    words = re.findall(r'[а-яa-zё]+', text.lower().replace('ё', 'е'))
    return [strip_age(w)[:5] for w in words
            if len(w) >= 4 and w not in NUMERALS and w.replace('е', 'ё') not in NUMERALS]


def letters(text):
    """Только буквы, без пробелов: распознавание рвёт слова, и пробел не значим."""
    return re.sub(r'[^а-яa-z]', '', text.lower().replace('ё', 'е'))


def char_coverage(quote, hay_letters):
    """Доля букв цитаты, покрытая упорядоченными совпадающими блоками дорожки."""
    q = letters(BRACKET.sub(' ', quote))
    if not q:
        return 1.0
    blocks = difflib.SequenceMatcher(None, q, hay_letters, autojunk=False).get_matching_blocks()
    return sum(b.size for b in blocks if b.size >= 4) / len(q)


def check_quote(quote, haystack, hay_letters):
    """True, если состав и порядок слов совпадают либо расхождение — только разрыв слова.

    Первая проверка идёт по основам слов. Если она падает, цитата всё равно
    принимается при почти полном посимвольном покрытии: так распознавание,
    разорвавшее слово надвое, не выдаётся за подмену.
    """
    ok = True
    for frag in re.split(r'…|\.\.\.', BRACKET.sub(' ', quote)):
        seq = stems(frag)
        if len(seq) < 2:
            continue
        i = 0
        for s in seq:
            try:
                i = haystack.index(s, i) + 1
            except ValueError:
                ok = False
                break
        if not ok:
            break
    if ok:
        return True
    return char_coverage(quote, hay_letters) >= 0.92


def page_text(slug):
    path = os.path.join(PAGES, '%s.md' % slug)
    if not os.path.exists(path):
        return ''
    return open(path, encoding='utf-8').read()


def body_of(text):
    """Тело страницы без frontmatter."""
    if text.startswith('---'):
        parts = text.split('---', 2)
        if len(parts) == 3:
            return parts[2]
    return text


def transcripts_for(text):
    """Пути к дорожкам: у Source — своя, у Concept — дорожки всех её источников."""
    cat = CATEGORY.search(text)
    cat = cat.group(1) if cat else ''
    ids = []
    if cat == 'Sources':
        m = VID.search(text)
        if m:
            ids.append(m.group(1))
    elif cat == 'Concepts':
        m = SOURCES.search(text)
        if m:
            for slug in (x.strip() for x in m.group(1).split(',')):
                if not slug:
                    continue
                mv = VID.search(page_text(slug))
                if mv:
                    ids.append(mv.group(1))
    paths = [os.path.join(RAW, '%s.ru.vtt' % i) for i in ids]
    return [p for p in paths if os.path.exists(p)]


def main(argv):
    strict = '--strict' in argv
    wanted = [a for a in argv if not a.startswith('--')]
    findings, checked, pages = [], 0, 0
    for name in sorted(os.listdir(PAGES)):
        if not name.endswith('.md'):
            continue
        slug = name[:-3]
        if wanted and slug not in wanted:
            continue
        text = open(os.path.join(PAGES, name), encoding='utf-8').read()
        vtts = transcripts_for(text)
        if not vtts:
            continue
        cat = CATEGORY.search(text)
        cat = cat.group(1) if cat else ''
        if cat == 'Sources':
            if '\n## Footnotes' not in text:
                continue
            scope = text[text.index('\n## Footnotes'):]
            quotes = QUOTE.findall(scope)
        else:
            scope = body_of(text)
            quotes = CITED.findall(scope)
        if not quotes:
            continue
        pages += 1
        plain = ' '.join(dedupe_vtt(v) for v in vtts)
        hay, hay_letters = stems(plain), letters(plain)
        for quote in quotes:
            if 'synthesis' in quote:
                continue
            checked += 1
            if not check_quote(quote, hay, hay_letters):
                findings.append((slug, quote.strip()))
    for slug, quote in findings:
        print('%-56s %s' % (slug[:56], quote[:96]))
    ok = checked - len(findings)
    print('\nстраниц: %d; цитат проверено: %d; дословных: %d (%.1f%%); нарушений: %d'
          % (pages, checked, ok, 100.0 * ok / checked if checked else 100.0, len(findings)))
    return 1 if (strict and findings) else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
