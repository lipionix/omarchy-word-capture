#!/bin/sh
# Run every test: sh tests/run.sh
# The logic tests need node; the writer tests run under sh, and under bash too
# when it is installed. Every suite runs even if one fails; the last line sums
# them up and the exit status is non-zero on any failure.
# sh tests/run.sh --perf also runs tests/perf.sh (not part of the default run).
here=$(cd "$(dirname -- "$0")" && pwd)
out=$(mktemp); trap 'rm -f "$out"' EXIT
passed=0 failed=0 skipped=0 broken=

suite() { # label command...
  label=$1; shift
  "$@" >"$out" 2>&1
  grep -v '^RESULT ' "$out" | sed -e "s/^FAIL: /FAIL: $label: /" -e "s/^skip: /skip: $label: /"
  result=$(grep '^RESULT ' "$out" | tail -n 1)
  if [ -z "$result" ]; then
    # No summary line: the suite crashed before it finished.
    echo "FAIL: $label stopped early"; tail -n 5 "$out" | sed 's/^/    /'
    broken="$broken $label"; return
  fi
  set -- $result
  passed=$((passed + $3)) failed=$((failed + $4)) skipped=$((skipped + $5))
}

if command -v node >/dev/null; then
  suite model node "$here/model.test.js"
else
  echo "FAIL: node not found; the model tests need it (https://nodejs.org)"
  broken="$broken model"
fi
suite "append(sh)" env SH=sh sh "$here/append.test.sh"
if command -v bash >/dev/null; then suite "append(bash)" env SH=bash sh "$here/append.test.sh"; fi
if [ "${1-}" = --perf ]; then sh "$here/perf.sh" || broken="$broken perf"; fi

summary="$passed passed, $failed failed, $skipped skipped"
if [ "$failed" = 0 ] && [ -z "$broken" ]; then echo "OK: $summary"; exit 0; fi
echo "FAILED: $summary${broken:+ (did not finish:$broken)}"
exit 1
