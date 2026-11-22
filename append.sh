#!/bin/sh
# Add one Markdown line to a words file, under its language heading.
#
#   append.sh <path> <line> [section]   add <line> at the end of "## <section>"
#                                       (created at the end of the file when
#                                       missing); no section: end of the file
#   append.sh --touch <path>            only make sure the file exists
#
# Arguments arrive as argv and reach awk through the environment, so nothing in
# them is parsed as code. "~" expands and a relative path resolves against
# $HOME; a symlink is followed. Missing folders are created. The new content is
# written to a temp file in the same folder, given the original's permissions
# and renamed over it (atomic). A lock on the folder serialises writers.
# Prints the resolved path; on failure one short line on stderr and exit 1.
set -u

fail() { printf '%s\n' "$1" >&2; exit 1; }

mode=add section=
case $# in
  2) if [ "$1" = "--touch" ]; then mode=touch path=$2 line=; else path=$1 line=$2; fi ;;
  3) path=$1 line=$2 section=$3 ;;
  *) fail "usage: append.sh <path> <line> [section] | --touch <path>" ;;
esac

case $path in
  "~") path=$HOME ;;
  "~/"*) path=$HOME/${path#"~/"} ;;
  /*) ;;
  *) path=$HOME/$path ;;
esac
[ -L "$path" ] && path=$(readlink -f -- "$path")

[ -d "$path" ] && fail "Is a directory: $path"
dir=$(dirname -- "$path")
mkdir -p -- "$dir" 2>/dev/null || fail "Cannot create folder: $dir"
true 2>/dev/null >>"$path" || fail "Permission denied: $path"

if [ "$mode" = touch ]; then printf '%s\n' "$path"; exit 0; fi

# Entries are one line; a section name is one trimmed line.
line=$(printf '%s' "$line" | tr '\n' ' ' | sed 's/[[:space:]]*$//')
section=$(printf '%s' "$section" | tr '\n' ' ' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
[ -z "$line" ] && fail "Nothing to write"

(
  flock 9 || exit 1
  tmp=$(mktemp -- "$dir/.word-capture.XXXXXX") || exit 1
  trap 'rm -f -- "$tmp"' EXIT
  WC_LINE=$line WC_SECTION=$section awk '
    function trim(s) { sub(/^[ \t\r]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
    # "## Name" -> "Name"; other headings of level 1-2 -> a non-matching marker.
    function heading(s,   t) {
      if (s ~ /^##[ \t]/) return trim(substr(s, 3))
      if (s ~ /^#[ \t]/ || s == "#" || s == "##") return "\001"
      return ""
    }
    { lines[++n] = $0 }
    END {
      want = ENVIRON["WC_SECTION"]; entry = ENVIRON["WC_LINE"]
      if (want == "") { for (i = 1; i <= n; i++) print lines[i]; print entry; exit }
      start = 0; stop = n
      for (i = 1; i <= n; i++) {
        h = heading(lines[i])
        if (start == 0) { if (h == want) start = i }
        else if (h != "") { stop = i - 1; break }
      }
      if (start == 0) {
        for (i = 1; i <= n; i++) print lines[i]
        if (n > 0 && trim(lines[n]) != "") print ""
        print "## " want; print ""; print entry; exit
      }
      # After the last non-blank line of the section, so blank lines before the
      # next heading stay where they are.
      at = start
      for (i = start + 1; i <= stop; i++) if (trim(lines[i]) != "") at = i
      if (at == start) { for (i = 1; i <= start; i++) print lines[i]; print ""; print entry; for (i = start + 1; i <= n; i++) print lines[i]; exit }
      for (i = 1; i <= n; i++) { print lines[i]; if (i == at) print entry }
    }
  ' "$path" >"$tmp" || exit 1
  chmod --reference="$path" -- "$tmp" 2>/dev/null
  mv -f -- "$tmp" "$path" || exit 1
  trap - EXIT
) 9<"$dir" || fail "Could not write: $path"

printf '%s\n' "$path"
