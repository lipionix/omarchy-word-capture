#!/bin/sh
# Tests for append.sh: sh tests/append.test.sh
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
run() { ${SH:-sh} "$here/append.sh" "$@" >/dev/null; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0
check() { # name expected-file actual-file
  if cmp -s "$2" "$3"; then pass=$((pass + 1)); else echo "FAIL: $1"; diff "$2" "$3" || true; exit 1; fi
}
expect() { printf '%s' "$2" >"$T/expected"; check "$1" "$T/expected" "$3"; }

# New file, new section.
run "$T/a.md" "- **casa** [Spanish]" Spanish
expect "new file gets a section" "## Spanish

- **casa** [Spanish]
" "$T/a.md"

# Existing section: appended at its end, before blank lines and the next heading.
printf '# Words\n\n## Spanish\n\n- **casa** [Spanish]\n\n## English\n\n- **house** [English]\n' >"$T/b.md"
run "$T/b.md" "- **perro** [Spanish] — dog" Spanish
expect "insert at end of existing section" "# Words

## Spanish

- **casa** [Spanish]
- **perro** [Spanish] — dog

## English

- **house** [English]
" "$T/b.md"

# Last section, file without trailing newline; ### stays inside the section.
printf '## English\n\n- **house** [English]\n### notes\n- **home** [English]' >"$T/c.md"
run "$T/c.md" "- **car** [English]" English
expect "last section, no trailing newline" "## English

- **house** [English]
### notes
- **home** [English]
- **car** [English]
" "$T/c.md"

# Ungrouped lines and a top title stay untouched; a missing section goes last.
printf '# Vocabulary\n- **simple** [English] — test\n' >"$T/d.md"
run "$T/d.md" "- **дом** [Russian]" Russian
expect "ungrouped lines untouched, new section at end" "# Vocabulary
- **simple** [English] — test

## Russian

- **дом** [Russian]
" "$T/d.md"

# Heading names with special characters are matched literally.
printf '## C++ (old) [x] .*\n\n- **a** [C++ (old) [x] .*]\n\n## Other\n' >"$T/e.md"
run "$T/e.md" '- **b** [C++ (old) [x] .*]' 'C++ (old) [x] .*'
expect "special characters in heading" "## C++ (old) [x] .*

- **a** [C++ (old) [x] .*]
- **b** [C++ (old) [x] .*]

## Other
" "$T/e.md"

# Empty section heading gets a blank line, then the entry.
printf '## Greek\n## Next\n' >"$T/f.md"
run "$T/f.md" "- **λόγος** [Greek]" Greek
expect "empty section" "## Greek

- **λόγος** [Greek]
## Next
" "$T/f.md"

# No section: plain append; shell metacharacters stay literal.
printf 'x' >"$T/g.md"
run "$T/g.md" '- **$(id)** `rm` "q" \n'
expect "no section, literal text" "x
- **\$(id)** \`rm\` \"q\" \\n
" "$T/g.md"

# Permissions are kept; a symlink keeps pointing at the real file.
printf '## A\n' >"$T/real.md"; chmod 640 "$T/real.md"; ln -s "$T/real.md" "$T/link.md"
run "$T/link.md" "- **x** [A]" A
[ -L "$T/link.md" ] && [ "$(stat -c %a "$T/real.md")" = 640 ] && pass=$((pass + 1)) || { echo "FAIL: perms/symlink"; exit 1; }

# Concurrent writers do not lose entries.
for i in $(seq 30); do ${SH:-sh} "$here/append.sh" "$T/h.md" "- **w$i** [L$((i % 3))]" "L$((i % 3))" >/dev/null & done; wait
[ "$(grep -c '^- \*\*w' "$T/h.md")" = 30 ] && [ "$(grep -c '^## ' "$T/h.md")" = 3 ] && pass=$((pass + 1)) || { echo "FAIL: concurrency"; cat "$T/h.md"; exit 1; }

# Multi-line input: newlines become spaces, the entry's end and the section's
# ends are trimmed, as the panel sends them.
run "$T/m.md" "- **one**
two  
" "  Multi
line "
expect "multi-line entry and section" "## Multi line

- **one** two
" "$T/m.md"

# Whitespace only is refused; a trailing slash is a folder, not created.
out=$(${SH:-sh} "$here/append.sh" "$T/w.md" "  
" A 2>&1 || true); [ "$out" = "Nothing to write" ] && [ ! -e "$T/w.md" ] && pass=$((pass + 1)) || { echo "FAIL: blank entry: $out"; exit 1; }
out=$(${SH:-sh} "$here/append.sh" "$T/slash/" x 2>&1 || true); [ "$out" = "Is a directory: $T/slash/" ] && [ ! -e "$T/slash" ] && pass=$((pass + 1)) || { echo "FAIL: trailing slash: $out"; exit 1; }

# A save into an existing file runs at most 6 programs besides sh itself:
# flock, mktemp, awk, chmod, mv (no dirname, mkdir, tr or sed).
mkdir "$T/shim"; : >"$T/execs"
for cmd in flock mktemp awk chmod mv mkdir dirname readlink tr sed cat; do
  real=$(command -v "$cmd") || continue
  printf '#!/bin/sh\necho %s >>"%s"\nexec %s "$@"\n' "$cmd" "$T/execs" "$real" >"$T/shim/$cmd"; chmod +x "$T/shim/$cmd"
done
printf '## A\n' >"$T/p.md"
PATH="$T/shim:$PATH" ${SH:-sh} "$here/append.sh" "$T/p.md" "- **x** [A]" A >/dev/null
n=$(wc -l <"$T/execs"); [ "$n" -le 6 ] && pass=$((pass + 1)) || { echo "FAIL: $n programs per save:"; cat "$T/execs"; exit 1; }
rm -rf "$T/shim" "$T/execs"

# --touch creates nothing but the file; errors are one line.
run --touch "$T/new/n.md"; [ -f "$T/new/n.md" ] && [ ! -s "$T/new/n.md" ] && pass=$((pass + 1))
out=$(${SH:-sh} "$here/append.sh" "$T" x 2>&1 || true); [ "$out" = "Is a directory: $T" ] && pass=$((pass + 1)) || { echo "FAIL: dir error: $out"; exit 1; }
[ -z "$(ls -A "$T" | grep '^\.word-capture')" ] && pass=$((pass + 1)) || { echo "FAIL: temp file left"; exit 1; }

echo "$pass passed"
