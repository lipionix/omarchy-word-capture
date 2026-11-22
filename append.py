#!/usr/bin/env python3
"""Append one Markdown line to a file: append.py <path> <line>.
With --touch instead of a line (append.py --touch <path>), only make sure the
file exists. Either way the resolved path is printed on success.

Arguments arrive as argv (no shell), so nothing in them is interpreted.
"~" expands; a relative path resolves against $HOME rather than the shell's
working directory. Missing parent folders are created. The line starts on a
fresh line even when the file does not end with a newline, and an exclusive
lock keeps two captures from interleaving. Errors print one short line to
stderr for the panel to show.
"""
import fcntl
import sys
from pathlib import Path


def main():
    touch = len(sys.argv) == 3 and sys.argv[1] == "--touch"
    if len(sys.argv) != 3:
        print("usage: append.py <path> <line> | append.py --touch <path>", file=sys.stderr)
        return 2
    path = Path(sys.argv[2] if touch else sys.argv[1]).expanduser()
    if not path.is_absolute():
        path = Path.home() / path
    line = "" if touch else sys.argv[2]
    if line and not line.endswith("\n"):
        line += "\n"
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("a+b") as f:
            fcntl.flock(f, fcntl.LOCK_EX)
            f.seek(0, 2)
            lead = b""
            if line and f.tell():
                f.seek(-1, 2)
                if f.read(1) != b"\n":
                    lead = b"\n"
            if line:
                f.write(lead + line.encode("utf-8"))
    except OSError as e:
        print(f"{e.strerror or e}: {e.filename or path}", file=sys.stderr)
        return 1
    print(path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
