#!/usr/bin/env python3
"""Read GitHub usernames from the current committers table on stdin."""
import re
import sys
from html.parser import HTMLParser


class Committers(HTMLParser):
    def __init__(self):
        super().__init__()
        self.section = False
        self.table = False
        self.done = False
        self.cell = None
        self.row = []
        self.headers = None
        self.usernames = []

    def handle_starttag(self, tag, attrs):
        if tag == "h2":
            if self.section and not self.done:
                raise ValueError("committers table not found")
            if dict(attrs).get("id") == "committers":
                self.section = True
        elif self.section and not self.done and tag == "table":
            self.table = True
        elif self.table and tag == "tr":
            self.row = []
        elif self.table and tag in ("th", "td"):
            self.cell = []

    def handle_data(self, data):
        if self.cell is not None:
            self.cell.append(data)

    def handle_endtag(self, tag):
        if self.table and tag in ("th", "td") and self.cell is not None:
            self.row.append("".join(self.cell).strip())
            self.cell = None
        elif self.table and tag == "tr" and self.row:
            if self.headers is None:
                self.headers = [cell.lower() for cell in self.row]
                if self.headers != ["name", "organization", "github username"]:
                    raise ValueError("unexpected committers table headings")
            else:
                if len(self.row) != len(self.headers):
                    raise ValueError("unexpected committer row")
                username = self.row[2]
                if not re.fullmatch(r"[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?", username):
                    raise ValueError("invalid GitHub username in committers table")
                self.usernames.append(username)
        elif self.table and tag == "table":
            self.table = False
            self.done = True


try:
    parser = Committers()
    parser.feed(sys.stdin.read())
    if not parser.done or not parser.usernames:
        raise ValueError("committers table is missing or empty")
    if len({name.lower() for name in parser.usernames}) != len(parser.usernames):
        raise ValueError("duplicate GitHub usernames in committers table")
    print("\n".join(parser.usernames))
except ValueError as error:
    sys.exit(f"Cannot read Islandora committers: {error}")
