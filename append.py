#!/usr/bin/env python3
"""Append one Markdown line to a file: append.py <path> <line>.

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
    if len(sys.argv) != 3:
        print("usage: append.py <path> <line>", file=sys.stderr)
        return 2
    path = Path(sys.argv[1]).expanduser()
    if not path.is_absolute():
        path = Path.home() / path
    line = sys.argv[2] if sys.argv[2].endswith("\n") else sys.argv[2] + "\n"
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("a+b") as f:
            fcntl.flock(f, fcntl.LOCK_EX)
            f.seek(0, 2)
            lead = b""
            if f.tell():
                f.seek(-1, 2)
                if f.read(1) != b"\n":
                    lead = b"\n"
            f.write(lead + line.encode("utf-8"))
    except OSError as e:
        print(f"{e.strerror or e}: {e.filename or path}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
