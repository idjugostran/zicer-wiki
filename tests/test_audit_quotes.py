"""Регрессия на словарь числительных в bin/audit-quotes.py.

SCHEMA разрешает писать числительные словами там, где дорожка даёт цифру.
Проверка это учитывает, выбрасывая числительные из сравнения, — но только
те, что перечислены в NUMERALS. Десятки от шестидесяти до девяноста и сотни
в наборе отсутствовали, из-за чего «девяносто семь процентов» в кавычках
давало ложное нарушение (найдено при разборе выпуска №213).
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'bin'))
import importlib.util

spec = importlib.util.spec_from_file_location(
    'audit_quotes',
    os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'bin', 'audit-quotes.py'))
audit_quotes = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit_quotes)


class TestNumerals(unittest.TestCase):
    def test_tens_are_complete(self):
        for w in ('двадцать', 'тридцать', 'сорок', 'пятьдесят', 'шестьдесят',
                  'семьдесят', 'восемьдесят', 'девяносто'):
            self.assertIn(w, audit_quotes.NUMERALS, w)

    def test_hundreds_are_complete(self):
        for w in ('сто', 'двести', 'триста', 'четыреста', 'пятьсот',
                  'шестьсот', 'семьсот', 'восемьсот', 'девятьсот'):
            self.assertIn(w, audit_quotes.NUMERALS, w)

    def test_percent_forms(self):
        for w in ('процентов', 'процента', 'процент'):
            self.assertIn(w, audit_quotes.NUMERALS, w)


class TestCitedInConcepts(unittest.TestCase):
    """В Concept-страницах проверяются только цитаты, помеченные локатором."""

    def find(self, text):
        return audit_quotes.CITED.findall(text)

    def test_quote_with_locator_is_picked_up(self):
        self.assertEqual(
            self.find('он сказал «мы становимся цензорами этого мира» [00:12:34]'),
            ['мы становимся цензорами этого мира'])

    def test_locator_may_follow_after_words(self):
        self.assertEqual(
            self.find('«эта тема одна из самых интересных» — говорит он [01:02:03]'),
            ['эта тема одна из самых интересных'])

    def test_quote_without_locator_is_ignored(self):
        self.assertEqual(self.find('приём назван «второй натурой» и работает'), [])

    def test_paraphrase_marks_are_ignored(self):
        self.assertEqual(self.find('позиция «взрослый прав по умолчанию» здесь снята'), [])

    def test_locator_of_a_later_quote_does_not_capture_earlier_one(self):
        text = ('«термин без локатора», а дальше совсем другая мысль, и ещё одна, '
                'и третья, и только потом «настоящая цитата» [00:01:02]')
        self.assertEqual(self.find(text), ['настоящая цитата'])


class TestTranscriptResolution(unittest.TestCase):
    def test_body_strips_frontmatter(self):
        body = audit_quotes.body_of('---\ntitle: X\nsummary: «пересказ»\n---\n\nтело «цитата»')
        self.assertNotIn('пересказ', body)
        self.assertIn('цитата', body)

    def test_body_of_page_without_frontmatter_is_whole_text(self):
        self.assertEqual(audit_quotes.body_of('просто текст'), 'просто текст')


class TestCompoundNumeralAdjectives(unittest.TestCase):
    """«тринадцатилетнему» в цитате против «13-летнему» в дорожке."""

    def test_prefix_is_stripped(self):
        self.assertEqual(audit_quotes.strip_age('тринадцатилетнему'), 'летнему')
        self.assertEqual(audit_quotes.strip_age('пятилетний'), 'летний')
        self.assertEqual(audit_quotes.strip_age('сорокалетняя'), 'летняя')

    def test_ordinary_words_untouched(self):
        for w in ('лететь', 'полетел', 'человек', 'летний'):
            self.assertEqual(audit_quotes.strip_age(w), w)

    def test_quote_and_track_agree_after_stripping(self):
        quote = audit_quotes.stems('зачем тринадцатилетнему мальчику нужна сестра')
        track = audit_quotes.stems('зачем 13-летнему мальчику нужна сестра')
        self.assertEqual(quote, track)


if __name__ == '__main__':
    unittest.main()
