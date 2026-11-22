#!/bin/sh
# Append one Markdown line to a file:  append.sh <path> <line>
# Only make sure the file exists:      append.sh --touch <path>
#
# Arguments arrive as argv (no shell parsing of their content). "~" expands and
# a relative path resolves against $HOME. Missing folders are created. The line
# starts on a fresh line even when the file lacks a trailing newline, and flock
# keeps two captures from interleaving. Prints the resolved path on success;
# on failure prints one short line to stderr and exits 1.
set -u

fail() { printf '%s\n' "$1" >&2; exit 1; }

if [ "$#" -eq 2 ] && [ "$1" = "--touch" ]; then
  path=$2 line=
elif [ "$#" -eq 2 ]; then
  path=$1 line=$2
else
  fail "usage: append.sh <path> <line> | append.sh --touch <path>"
fi

case $path in
  "~") path=$HOME ;;
  "~/"*) path=$HOME/${path#"~/"} ;;
  /*) ;;
  *) path=$HOME/$path ;;
esac

[ -d "$path" ] && fail "Is a directory: $path"
dir=$(dirname -- "$path")
mkdir -p -- "$dir" 2>/dev/null || fail "Cannot create folder: $dir"
true 2>/dev/null >>"$path" || fail "Permission denied: $path"

if [ -n "$line" ]; then
  case $line in *"
") ;; *) line="$line
" ;; esac
  (
    flock 9 || exit 1
    # $(...) drops a trailing newline, so this is empty unless the last byte is not one.
    [ -s "$path" ] && [ -n "$(tail -c 1 -- "$path")" ] && printf '\n' >&9
    printf '%s' "$line" >&9
  ) 9>>"$path" || fail "Could not write: $path"
fi

printf '%s\n' "$path"
