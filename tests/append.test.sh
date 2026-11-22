#!/bin/sh
# Tests for append.sh, the writer: sh tests/append.test.sh
# SH=bash runs append.sh under another shell. The last line is a summary
# that tests/run.sh reads.
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
SH=${SH:-sh}
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

# Each test is a t_ function and runs in its own folder $D. It must make at
# least one check; a test that makes none counts as failed.
passed=0 failed=0 skipped=0 checks=0 bad=0 name= skip_reason=
note() { printf '%s\n' "$@" | sed 's/^/    /'; }
fail() { bad=1; echo "FAIL: $name: $1"; shift; [ $# -gt 0 ] && note "$@"; return 0; }
# ok "what" command...: the command must succeed.
ok() { checks=$((checks + 1)); what=$1; shift; "$@" || fail "$what"; }
# same file "text": the file holds exactly this text.
same() {
  checks=$((checks + 1))
  printf '%s' "$2" >"$T/expected"
  cmp -s "$T/expected" "$1" || fail "$(basename "$1") differs (- expected, + actual)" "$(diff -u "$T/expected" "$1" | tail -n +3)"
}
# says "message" args...: append.sh fails with exactly this one-line message.
says() {
  checks=$((checks + 1)); want=$1; shift
  if got=$($SH "$here/append.sh" "$@" 2>&1 >/dev/null); then fail "expected an error, it succeeded"
  elif [ "$got" != "$want" ]; then fail "wrong error" "expected: $want" "got:      $got"; fi
}
skip() { skip_reason=$1; }
save() { $SH "$here/append.sh" "$@" >/dev/null || fail "append.sh $* failed"; }
no_temp_files() { ok "no temp file left in $(basename "$1")" [ -z "$(ls -A "$1" | grep '^\.word-capture')" ]; }

t_new_file_gets_a_section() {
  save "$D/w.md" "- **casa** [Spanish]" Spanish
  same "$D/w.md" "## Spanish

- **casa** [Spanish]
"
  no_temp_files "$D"
}

t_entry_goes_to_the_end_of_its_section() {
  printf '# Words\n\n## Spanish\n\n- **casa** [Spanish]\n\n## English\n\n- **house** [English]\n' >"$D/w.md"
  save "$D/w.md" "- **perro** [Spanish] — dog" Spanish
  same "$D/w.md" "# Words

## Spanish

- **casa** [Spanish]
- **perro** [Spanish] — dog

## English

- **house** [English]
"
}

t_captures_keep_their_order() {
  for w in uno dos tres; do save "$D/w.md" "- **$w** [Spanish]" Spanish; done
  same "$D/w.md" "## Spanish

- **uno** [Spanish]
- **dos** [Spanish]
- **tres** [Spanish]
"
}

t_new_sections_follow_first_capture_order() {
  save "$D/w.md" "- **casa** [Spanish]" Spanish
  save "$D/w.md" "- **дом** [Russian]" Russian
  save "$D/w.md" "- **perro** [Spanish]" Spanish
  same "$D/w.md" "## Spanish

- **casa** [Spanish]
- **perro** [Spanish]

## Russian

- **дом** [Russian]
"
}

t_last_section_without_trailing_newline() {
  printf '## English\n\n- **house** [English]\n### notes\n- **home** [English]' >"$D/w.md"
  save "$D/w.md" "- **car** [English]" English
  same "$D/w.md" "## English

- **house** [English]
### notes
- **home** [English]
- **car** [English]
"
}

t_other_text_is_left_alone() {
  printf '# Vocabulary\n- **simple** [English] — test\n' >"$D/w.md"
  save "$D/w.md" "- **дом** [Russian]" Russian
  same "$D/w.md" "# Vocabulary
- **simple** [English] — test

## Russian

- **дом** [Russian]
"
}

t_heading_names_are_literal() {
  printf '## C++ (old) [x] .*\n\n- **a** [C++ (old) [x] .*]\n\n## Other\n' >"$D/w.md"
  save "$D/w.md" '- **b** [C++ (old) [x] .*]' 'C++ (old) [x] .*'
  same "$D/w.md" "## C++ (old) [x] .*

- **a** [C++ (old) [x] .*]
- **b** [C++ (old) [x] .*]

## Other
"
}

t_empty_section_gets_a_blank_line_first() {
  printf '## Greek\n## Next\n' >"$D/w.md"
  save "$D/w.md" "- **λόγος** [Greek]" Greek
  same "$D/w.md" "## Greek

- **λόγος** [Greek]
## Next
"
}

t_no_section_appends_literal_text() {
  printf 'x' >"$D/w.md"
  save "$D/w.md" '- **$(id)** `rm` "q" \n'
  same "$D/w.md" 'x
- **$(id)** `rm` "q" \n
'
}

t_multi_line_input_becomes_one_line() {
  save "$D/w.md" "- **one**
two  
" "  Multi
line "
  same "$D/w.md" "## Multi line

- **one** two
"
}

t_missing_folders_are_created() {
  save "$D/a/b/w.md" "- **x** [A]" A
  same "$D/a/b/w.md" "## A

- **x** [A]
"
}

t_touch_creates_an_empty_file_only() {
  save --touch "$D/new/w.md"
  ok "file exists" [ -f "$D/new/w.md" ]
  ok "file is empty" [ ! -s "$D/new/w.md" ]
  printf 'keep\n' >"$D/k.md"; save --touch "$D/k.md"
  same "$D/k.md" "keep
"
}

t_prints_the_resolved_path() {
  out=$(HOME=$D $SH "$here/append.sh" --touch "notes/w.md")
  ok "relative path resolves under HOME" [ "$out" = "$D/notes/w.md" ]
  out=$(HOME=$D $SH "$here/append.sh" "~/t.md" "- **x**")
  ok "~ resolves to HOME" [ "$out" = "$D/t.md" ]
}

t_symlink_is_followed() {
  printf '## A\n' >"$D/real.md"; ln -s "$D/real.md" "$D/link.md"
  save "$D/link.md" "- **x** [A]" A
  ok "link is still a link" [ -L "$D/link.md" ]
  same "$D/real.md" "## A

- **x** [A]
"
  ln -s "$D/later.md" "$D/dangling.md"
  save "$D/dangling.md" "- **y** [A]" A
  ok "dangling link still a link" [ -L "$D/dangling.md" ]
  ok "target created" [ -f "$D/later.md" ]
}

t_permissions_are_kept() {
  printf '## A\n' >"$D/w.md"; chmod 640 "$D/w.md"
  save "$D/w.md" "- **x** [A]" A
  ok "mode stays 640" [ "$(stat -c %a "$D/w.md")" = 640 ]
}

acl_ready() {
  command -v setfacl >/dev/null && command -v getfacl >/dev/null \
    && printf '## A\n' >"$1" && chmod 640 "$1" && setfacl -m u:nobody:--- "$1" 2>/dev/null
}

t_access_list_is_kept() {
  acl_ready "$D/w.md" || { skip "no setfacl or no ACL support in $(dirname "$T")"; return; }
  before=$(getfacl -cp "$D/w.md")
  save "$D/w.md" "- **x** [A]" A
  ok "ACL unchanged" [ "$(getfacl -cp "$D/w.md")" = "$before" ]
}

# A folder where file attributes cannot be copied (as on FAT) is simulated
# with a cp that always fails.
t_access_list_that_cannot_be_kept_stops_the_save() {
  acl_ready "$D/w.md" || { skip "no setfacl or no ACL support in $(dirname "$T")"; return; }
  mkdir "$D/bin"; printf '#!/bin/sh\nexit 1\n' >"$D/bin/cp"; chmod +x "$D/bin/cp"
  cp "$D/w.md" "$D/copy"
  saved_path=$PATH; PATH="$D/bin:$PATH"
  says "Cannot keep the file's access list: $D/w.md" "$D/w.md" "- **y** [A]" A
  ok "file untouched" cmp -s "$D/w.md" "$D/copy"
  printf '## A\n' >"$D/plain.md"; chmod 604 "$D/plain.md"
  save "$D/plain.md" "- **y** [A]" A
  PATH=$saved_path
  ok "without an ACL the mode still carries over" [ "$(stat -c %a "$D/plain.md")" = 604 ]
  no_temp_files "$D"
}

t_concurrent_saves_lose_nothing() {
  i=0; while [ $i -lt 30 ]; do
    i=$((i + 1)); $SH "$here/append.sh" "$D/w.md" "- **w$i** [L$((i % 3))]" "L$((i % 3))" >/dev/null &
  done; wait
  ok "30 entries" [ "$(grep -c '^- \*\*w' "$D/w.md")" = 30 ]
  ok "3 sections" [ "$(grep -c '^## ' "$D/w.md")" = 3 ]
  ok "each section once" [ "$(grep '^## ' "$D/w.md" | sort -u | wc -l)" = 3 ]
  no_temp_files "$D"
}

t_blank_entry_is_refused() {
  says "Nothing to write" "$D/w.md" "  
" A
  ok "no file created" [ ! -e "$D/w.md" ]
}

t_folder_paths_are_refused() {
  says "Is a directory: $D" "$D" x
  says "Is a directory: $D/slash/" "$D/slash/" x
  ok "no folder created" [ ! -e "$D/slash" ]
}

t_unwritable_targets_are_reported() {
  [ "$(id -u)" = 0 ] && { skip "running as root"; return; }
  printf '## A\n' >"$D/ro.md"; chmod 444 "$D/ro.md"
  says "Permission denied: $D/ro.md" "$D/ro.md" "- **x** [A]" A
  mkdir "$D/locked"; chmod 555 "$D/locked"
  says "Cannot create folder: $D/locked/sub" "$D/locked/sub/w.md" "- **x** [A]" A
  chmod 755 "$D/locked"
  no_temp_files "$D"
}

# Every t_ function above, in order. A function missing here fails the run.
tests="t_new_file_gets_a_section t_entry_goes_to_the_end_of_its_section
t_captures_keep_their_order t_new_sections_follow_first_capture_order
t_last_section_without_trailing_newline t_other_text_is_left_alone
t_heading_names_are_literal t_empty_section_gets_a_blank_line_first
t_no_section_appends_literal_text t_multi_line_input_becomes_one_line
t_missing_folders_are_created t_touch_creates_an_empty_file_only
t_prints_the_resolved_path t_symlink_is_followed t_permissions_are_kept
t_access_list_is_kept t_access_list_that_cannot_be_kept_stops_the_save
t_concurrent_saves_lose_nothing t_blank_entry_is_refused
t_folder_paths_are_refused t_unwritable_targets_are_reported"

for name in $(sed -n 's/^\(t_[a-z_]*\)() {$/\1/p' "$0"); do
  case " $(echo $tests) " in *" $name "*) ;; *) echo "FAIL: $name is not listed in tests"; failed=$((failed + 1)) ;; esac
done

for name in $tests; do
  D=$T/$name; mkdir "$D"
  checks=0 bad=0 skip_reason=
  $name
  if [ -n "$skip_reason" ]; then echo "skip: $name: $skip_reason"; skipped=$((skipped + 1))
  elif [ $checks = 0 ]; then echo "FAIL: $name: made no checks"; failed=$((failed + 1))
  elif [ $bad = 1 ]; then failed=$((failed + 1))
  else passed=$((passed + 1)); fi
done

echo "RESULT append($SH) $passed $failed $skipped"
[ $failed = 0 ]
