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


if __name__ == '__main__':
    unittest.main()
