import importlib.util
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).parents[1] / "bin" / "lint-mechanical.py"
SPEC = importlib.util.spec_from_file_location("lint_mechanical", MODULE_PATH)
lint = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(lint)


class MalformedLinkTests(unittest.TestCase):
    def test_reports_markdown_link_missing_outer_closing_bracket(self):
        detector = getattr(lint, "malformed_links_in", lambda _text: [])

        self.assertEqual(
            detector("See [[target](pages/target.md) for details."),
            ["[[target](pages/target.md)"],
        )


class CitationTests(unittest.TestCase):
    def test_treats_footnote_before_colon_in_prose_as_a_use(self):
        text = "Three reasons[^2]: first, second, third.\n\n[^2]: source [00:00:01] — quote"

        self.assertEqual(lint.citation_issues_in(text), [])

    def test_reports_missing_and_unused_footnote_definitions(self):
        detector = getattr(lint, "citation_issues_in", lambda _text: [])
        text = "Claim.[^missing]\n\n[^unused]: source [00:00:01]-[00:00:02] [synthesis] — note"

        self.assertEqual(
            detector(text),
            [
                {"type": "missing_definition", "ref": "missing"},
                {"type": "unused_definition", "ref": "unused"},
            ],
        )

    def test_reports_duplicate_footnote_definitions(self):
        text = "Claim.[^1]\n\n[^1]: first source\n[^1]: second source"

        self.assertEqual(
            lint.citation_issues_in(text),
            [{"type": "duplicate_definition", "ref": "1", "count": 2}],
        )


class CoverageTests(unittest.TestCase):
    def test_warns_when_long_transcript_page_has_too_few_cases(self):
        detector = getattr(lint, "coverage_warning_for", lambda _body: None)
        body = (
            "## Summary\n\nFirst case.[^1]\n\nSecond case.[^2]\n\n"
            "## Key Takeaways\n\n- Two cases.\n\n## Footnotes\n\n"
            "[^1]: source [00:01:00]-[00:10:00] [synthesis] — first\n"
            "[^2]: source [01:02:00]-[01:05:00] [synthesis] — second"
        )

        self.assertEqual(
            detector(body),
            {"summary_blocks": 2, "timestamp_ranges": 2, "duration_seconds": 3900},
        )

    def test_reports_invalid_and_reversed_timestamp_ranges(self):
        detector = getattr(lint, "citation_issues_in", lambda _text: [])
        text = (
            "First.[^1] Second.[^2]\n\n"
            "[^1]: source [00:61:00]-[00:62:00] [synthesis] — invalid\n"
            "[^2]: source [00:10:00]-[00:09:59] [synthesis] — reversed"
        )

        self.assertEqual(
            detector(text),
            [
                {"type": "invalid_timestamp", "ref": "1", "value": "00:61:00"},
                {"type": "invalid_timestamp", "ref": "1", "value": "00:62:00"},
                {
                    "type": "reversed_timestamp_range",
                    "ref": "2",
                    "value": "00:10:00-00:09:59",
                },
            ],
        )


if __name__ == "__main__":
    unittest.main()
