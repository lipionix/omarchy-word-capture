#!/bin/sh
# Optional performance check, not part of the default run:
#   sh tests/perf.sh   (or sh tests/run.sh --perf)
# Counts the programs one save starts besides sh itself, through logging
# wrappers put first on PATH, and times 50 saves into a 5000-line file. The
# budget is 2 programs besides sh: flock and awk.
here=$(cd "$(dirname -- "$0")/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir "$T/bin"
for cmd in flock mktemp awk cp chmod mv mkdir dirname readlink tr sed cat ls; do
  real=$(command -v "$cmd") || continue
  printf '#!/bin/sh\necho %s >>"%s"\nexec %s "$@"\n' "$cmd" "$T/programs" "$real" >"$T/bin/$cmd"
  chmod +x "$T/bin/$cmd"
done
printf '## A\n' >"$T/w.md"; : >"$T/programs"
PATH="$T/bin:$PATH" sh "$here/append.sh" "$T/w.md" "- **x** [A]" A >/dev/null
n=$(wc -l <"$T/programs")
echo "perf: one save starts $n programs: $(tr '\n' ' ' <"$T/programs")"

awk 'BEGIN { for (s = 0; s < 5; s++) { print "## L" s; print ""; for (i = 0; i < 1000; i++) print "- **w" s "_" i "** [L" s "]"; print "" } }' >"$T/big.md"
start=$(date +%s%N)
i=0; while [ $i -lt 50 ]; do i=$((i + 1)); sh "$here/append.sh" "$T/big.md" "- **x$i** [L2]" L2 >/dev/null; done
echo "perf: $(( ($(date +%s%N) - start) / 50000000 )) ms per save into a 5000-line file"
[ "$n" -le 2 ] || { echo "FAIL: perf: $n programs per save besides sh, budget 2"; exit 1; }
