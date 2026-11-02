#!/usr/bin/env python3
"""Validate resources/programs/programs.json and optionally print the expanded steps.

Usage:
    scripts/check_programs.py            # validate, print one summary line per program
    scripts/check_programs.py --show     # also print every step of every program
    scripts/check_programs.py --show "Week 1"   # only programs with this name

The expansion here mirrors Programs.expand() in source/Program.mc.
Format: docs/program-format.md
"""
import json
import sys
from pathlib import Path

PATH = Path(__file__).resolve().parent.parent / "resources" / "programs" / "programs.json"
TYPES = ("hang", "rest")
MAX_DEPTH = 4


class FormatError(Exception):
    pass


def check_nodes(nodes, where, depth=0):
    if not isinstance(nodes, list) or not nodes:
        raise FormatError(f"{where}: must be a non-empty list of steps")
    if depth > MAX_DEPTH:
        raise FormatError(f"{where}: repeats nested deeper than {MAX_DEPTH}")
    for i, node in enumerate(nodes):
        here = f"{where}[{i}]"
        if not isinstance(node, dict):
            raise FormatError(f"{here}: must be an object")
        if "repeat" in node:
            allowed = {"repeat", "name", "do", "between"}
            extra = set(node) - allowed
            if extra:
                raise FormatError(f"{here}: unknown keys {sorted(extra)}")
            n = node["repeat"]
            if not isinstance(n, int) or isinstance(n, bool) or n < 1:
                raise FormatError(f"{here}.repeat: must be an integer >= 1")
            if "name" in node and not isinstance(node["name"], str):
                raise FormatError(f"{here}.name: must be a string")
            if "do" not in node:
                raise FormatError(f"{here}: a repeat needs a 'do' list")
            check_nodes(node["do"], f"{here}.do", depth + 1)
            if "between" in node:
                check_nodes(node["between"], f"{here}.between", depth + 1)
        else:
            allowed = {"type", "sec", "label"}
            extra = set(node) - allowed
            if extra:
                raise FormatError(f"{here}: unknown keys {sorted(extra)}")
            if node.get("type") not in TYPES:
                raise FormatError(f"{here}.type: must be one of {TYPES}")
            sec = node.get("sec")
            if not isinstance(sec, int) or isinstance(sec, bool) or sec < 1:
                raise FormatError(f"{here}.sec: must be an integer >= 1")
            if "label" in node and not isinstance(node["label"], str):
                raise FormatError(f"{here}.label: must be a string")


def expand(nodes, counters, out):
    """counters: list of (name, index, total), innermost first."""
    for node in nodes:
        if "repeat" in node:
            total = node["repeat"]
            name = node.get("name")
            for n in range(1, total + 1):
                inner = ([(name, n, total)] + counters) if name else counters
                expand(node["do"], inner, out)
                if n < total and "between" in node:
                    expand(node["between"], inner, out)
        else:
            out.append((node["type"], node["sec"], node.get("label"), counters))


def progress(counters):
    return "   ".join(f"{n} {i}/{t}" for n, i, t in reversed(counters))


def fmt(sec):
    return f"{sec // 60}:{sec % 60:02d}" if sec >= 60 else f"{sec}s"


def main(argv):
    show = "--show" in argv
    only = [a for a in argv if not a.startswith("--")]

    try:
        data = json.loads(PATH.read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        print(f"{PATH}: {e}", file=sys.stderr)
        return 1

    try:
        if data.get("format") != 1:
            raise FormatError("format: must be 1")
        folders = data.get("folders")
        if not isinstance(folders, list) or not folders:
            raise FormatError("folders: must be a non-empty list")
        for f, folder in enumerate(folders):
            fw = f"folders[{f}]"
            if not isinstance(folder.get("name"), str) or not folder["name"]:
                raise FormatError(f"{fw}.name: required string")
            progs = folder.get("programs")
            if not isinstance(progs, list) or not progs:
                raise FormatError(f"{fw}.programs: must be a non-empty list")
            for p, prog in enumerate(progs):
                pw = f"{fw}.programs[{p}]"
                if not isinstance(prog.get("name"), str) or not prog["name"]:
                    raise FormatError(f"{pw}.name: required string")
                check_nodes(prog.get("steps"), f"{pw}.steps")
    except FormatError as e:
        print(f"programs.json: {e}", file=sys.stderr)
        return 1

    for folder in data["folders"]:
        print(folder["name"])
        for prog in folder["programs"]:
            steps = []
            expand(prog["steps"], [], steps)
            hangs = sum(1 for s in steps if s[0] == "hang")
            total = sum(s[1] for s in steps)
            print(f"  {prog['name']}: {hangs} hangs, {fmt(total)} total, {len(steps)} steps")
            if show and (not only or prog["name"] in only):
                for kind, sec, label, counters in steps:
                    print(f"      {(label or kind.upper()):<9} {fmt(sec):>5}   {progress(counters)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
