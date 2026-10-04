#!/usr/bin/env python3
"""Grober Klammer-Check für Swift-Dateien (kein swiftc auf dem Server): zählt { } ( ) [ ]
außerhalb von Strings und Kommentaren und meldet, wo es nicht aufgeht.

    python3 tools/brace-check.py ios/Dopa/*.swift
"""
import sys

PAIRS = {"}": "{", ")": "(", "]": "["}


def check(path):
    text = open(path, encoding="utf-8").read()
    stack = []
    i, line = 0, 1
    in_block = 0
    while i < len(text):
        c = text[i]
        nxt = text[i + 1] if i + 1 < len(text) else ""
        if c == "\n":
            line += 1
        if in_block:
            if c == "*" and nxt == "/":
                in_block -= 1
                i += 1
            elif c == "/" and nxt == "*":
                in_block += 1
                i += 1
        elif c == "/" and nxt == "/":
            while i < len(text) and text[i] != "\n":
                i += 1
            continue
        elif c == "/" and nxt == "*":
            in_block = 1
            i += 1
        elif c == '"' or (c == "#" and nxt == '"'):
            # String (auch #"…"# und """…"""); Interpolation \( … ) wird übersprungen
            raw = c == "#"
            if raw:
                i += 1
            triple = text.startswith('"""', i)
            end = ('"""' if triple else '"') + ("#" if raw else "")
            i += 3 if triple else 1
            depth = 0
            while i < len(text):
                if text[i] == "\n":
                    line += 1
                if not raw and text[i] == "\\" and text[i + 1:i + 2] == "(":
                    depth += 1
                    i += 2
                    continue
                if depth and text[i] == "(":
                    depth += 1
                elif depth and text[i] == ")":
                    depth -= 1
                elif not depth and not raw and text[i] == "\\":
                    i += 2
                    continue
                elif not depth and text.startswith(end, i):
                    i += len(end) - 1
                    break
                i += 1
        elif c in "{([":
            stack.append((c, line))
        elif c in "})]":
            if not stack or stack[-1][0] != PAIRS[c]:
                print(f"{path}:{line}: unerwartetes '{c}'")
                return False
            stack.pop()
        i += 1
    if stack:
        print(f"{path}:{stack[-1][1]}: '{stack[-1][0]}' nicht geschlossen")
        return False
    return True


ok = all([check(p) for p in sys.argv[1:]])
print("Klammern ok" if ok else "Klammern kaputt")
sys.exit(0 if ok else 1)
