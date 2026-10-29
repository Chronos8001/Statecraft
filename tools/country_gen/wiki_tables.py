"""Lecture des tableaux HTML de Wikipédia (pages récupérées via l'API REST)."""

from __future__ import annotations

import re
from html.parser import HTMLParser

SKIPPED_TAGS = {"sup", "style", "script"}
NUMBER_PATTERN = re.compile(r"-?\d[\d,\.]*")


class _TableParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.tables: list[list[list[str]]] = []
        self._stack: list[list[list[str]]] = []
        self._row: list[str] | None = None
        self._cell: list[str] | None = None
        self._skip = 0
        self._spans: list[int] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag in SKIPPED_TAGS:
            self._skip += 1
        elif tag == "table":
            self._stack.append([])
        elif tag == "tr" and self._stack:
            self._row = []
        elif tag in ("td", "th") and self._row is not None:
            self._cell = []
            span = dict(attrs).get("colspan") or "1"
            self._spans.append(int(span) if span.isdigit() else 1)
        elif tag == "br" and self._cell is not None:
            self._cell.append(" ")

    def handle_endtag(self, tag: str) -> None:
        if tag in SKIPPED_TAGS:
            self._skip = max(0, self._skip - 1)
        elif tag in ("td", "th") and self._cell is not None and self._row is not None:
            text = " ".join("".join(self._cell).split())
            span = self._spans.pop() if self._spans else 1
            self._row.extend([text] * span)
            self._cell = None
        elif tag == "tr" and self._row is not None and self._stack:
            self._stack[-1].append(self._row)
            self._row = None
        elif tag == "table" and self._stack:
            self.tables.append(self._stack.pop())

    def handle_data(self, data: str) -> None:
        if self._cell is not None and self._skip == 0:
            self._cell.append(data)


def read_tables(html: str) -> list[list[list[str]]]:
    parser = _TableParser()
    parser.feed(html)
    return parser.tables


def parse_number(text: str) -> float | None:
    """Premier nombre d'une cellule (« 1,234.5 », « 31.8 trillion »…), None si absent."""
    match = NUMBER_PATTERN.search(text.replace("−", "-"))
    if not match:
        return None
    try:
        return float(match.group(0).replace(",", ""))
    except ValueError:
        return None
