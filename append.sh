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
# written to a temp file in the same folder, given the original's mode bits,
# access list (POSIX ACL), owner and group, and renamed over it (atomic). If
# the owner or group cannot be carried over, the content is written into the
# original file instead. Either way a save never widens who can read it. A lock on the folder serialises writers.
# Prints the resolved path; on failure one short line on stderr and exit 1.
set -u

fail() { printf '%s\n' "$1" >&2; exit 1; }

mode=add section=
case $# in
  2) if [ "$1" = "--touch" ]; then mode=touch path=$2 line=; else path=$1 line=$2; fi ;;
  3) path=$1 line=$2 section=$3 ;;
  *) fail "usage: append.sh <path> <line> [section] | --touch <path>" ;;
esac

# Entries are one line and a section name one trimmed line (done in awk);
# a blank entry is refused before anything is created.
if [ "$mode" = add ]; then
  case $line in *[![:space:]]*) ;; *) fail "Nothing to write" ;; esac
fi

case $path in
  "~") path=$HOME ;;
  "~/"*) path=$HOME/${path#"~/"} ;;
  /*) ;;
  *) path=$HOME/$path ;;
esac
[ -L "$path" ] && path=$(readlink -f -- "$path")

# Only builtins up to the lock: a save runs sh, flock, mktemp, awk, cp
# and mv (plus mkdir for a new folder, readlink for a symlink).
case $path in */) fail "Is a directory: $path" ;; esac
[ -d "$path" ] && fail "Is a directory: $path"
dir=${path%/*}
[ -n "$dir" ] || dir=/
[ -d "$dir" ] || mkdir -p -- "$dir" 2>/dev/null || fail "Cannot create folder: $dir"
true 2>/dev/null >>"$path" || fail "Permission denied: $path"

if [ "$mode" = touch ]; then printf '%s\n' "$path"; exit 0; fi

(
  flock 9 || exit 1
  tmp=$(mktemp -- "$dir/.word-capture.XXXXXX") || exit 1
  trap 'rm -f -- "$tmp"' EXIT
  # The C locale makes tolower() fold A-Z only, the same in every awk.
  LC_ALL=C WC_LINE=$line WC_SECTION=$section awk '
    function trim(s) { sub(/^[ \t\r]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
    # One line: newlines become spaces, outer whitespace goes.
    function oneLine(s) { gsub(/\n/, " ", s); sub(/^[ \t\r\v\f]+/, "", s); sub(/[ \t\r\v\f]+$/, "", s); return s }
    # "## Name" -> "Name"; other headings of level 1-2, and "##" without a
    # name, -> a non-matching marker (they end a section).
    function heading(s,   t) {
      sub(/\r$/, "", s)
      if (s ~ /^##[ \t]/) { t = trim(substr(s, 3)); return t == "" ? "\001" : t }
      if (s ~ /^#[ \t]/ || s == "#" || s == "##") return "\001"
      return ""
    }
    # How section names compare: case of A-Z and runs of spaces ignored.
    # Model.js (sectionKey) compares the same way for the toast counts.
    function key(s) { s = trim(s); gsub(/[ \t]+/, " ", s); return tolower(s) }
    # New lines take the line ending of the first line of the file, so a
    # CRLF file stays CRLF. Existing lines are written back as they were.
    function put(s) { printf "%s%s\n", s, crlf ? "\r" : "" }
    function keep(i) { if (i == n && crlf && lines[i] !~ /\r$/) put(lines[i]); else print lines[i] }
    { lines[++n] = $0 }
    END {
      crlf = n > 0 && lines[1] ~ /\r$/
      want = oneLine(ENVIRON["WC_SECTION"]); entry = ENVIRON["WC_LINE"]
      # Leading whitespace of an entry is kept, as before; only the end trims.
      gsub(/\n/, " ", entry); sub(/[ \t\r\v\f]+$/, "", entry)
      if (want == "") { for (i = 1; i <= n; i++) keep(i); put(entry); exit }
      # An existing heading is reused as written: "## spanish " takes Spanish.
      wanted = key(want); start = 0; stop = n
      for (i = 1; i <= n; i++) {
        h = heading(lines[i])
        if (start == 0) { if (h != "" && key(h) == wanted) start = i }
        else if (h != "") { stop = i - 1; break }
      }
      if (start == 0) {
        for (i = 1; i <= n; i++) keep(i)
        if (n > 0 && trim(lines[n]) != "") put("")
        put("## " want); put(""); put(entry); exit
      }
      # After the last non-blank line of the section, so blank lines before the
      # next heading stay where they are.
      at = start
      for (i = start + 1; i <= stop; i++) if (trim(lines[i]) != "") at = i
      if (at == start) { for (i = 1; i <= start; i++) keep(i); put(""); put(entry); for (i = start + 1; i <= n; i++) keep(i); exit }
      for (i = 1; i <= n; i++) { keep(i); if (i == at) put(entry) }
    }
  ' "$path" >"$tmp" || exit 1
  # The temp file starts private (0600). cp copies mode and ACL in one go;
  # where that fails (a filesystem without permissions, like FAT), plain mode
  # bits do, unless the file has an ACL that would be lost: then stop.
  if ! cp --attributes-only --preserve=mode,ownership -- "$path" "$tmp" 2>/dev/null; then
    case $(ls -ld -- "$path") in ??????????+*) exit 3 ;; esac
    chmod --reference="$path" -- "$tmp" 2>/dev/null
  fi
  # The replacement must also have the original owner and group. cp reports
  # success when it cannot set them (a shared file owned by someone else, or
  # a group the saver is not in), so check. The usual case, a file of ours
  # in our group, is settled by test builtins without starting stat. If they
  # differ, write the new content into the file itself instead: the same
  # file keeps its owner, group, mode and ACL, at the cost of an atomic swap.
  if { [ -O "$path" ] && [ -G "$path" ] && [ -O "$tmp" ] && [ -G "$tmp" ]; } \
    || [ "$(stat -c %u:%g -- "$path")" = "$(stat -c %u:%g -- "$tmp")" ]; then
    mv -f -- "$tmp" "$path" || exit 1
    trap - EXIT
  else
    cat -- "$tmp" >"$path" || exit 1
  fi
) 9<"$dir"
case $? in
  0) ;;
  3) fail "Cannot keep the file's access list: $path" ;;
  *) fail "Could not write: $path" ;;
esac

printf '%s\n' "$path"
