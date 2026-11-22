# Word Capture

An Omarchy bar widget for collecting vocabulary. Click the book icon, type a
word, optionally add context, press Enter. One Markdown line goes to the end
of its language's section in your vocabulary file, and a toast confirms it with
your counts, e.g. "128 words, 42 in Spanish" ("Already had it. 128 words, 42
in Spanish" when the word was in the file already). Click the toast to open the file.

```markdown
# Vocabulary            <- anything outside sections is left alone

## Spanish

- **casa** [Spanish] — la casa es grande
- **perro** [Spanish]   <- new Spanish entries land here

## Russian

- **дом** [Russian]
```

A missing `## <Language>` section is created at the end of the file. The
`[Language]` tag stays in every line, so a line moved elsewhere keeps its
language. Text outside sections (a title, notes) is left as it is.

`\`, `*` and `_` in the word and the context are backslash-escaped, so
`snake_case` or `**x**` cannot break the bold word. A multi-line context
stays one list line, its lines joined with ` / `.

## Use

| Key / action        | Does                                                   |
|---------------------|--------------------------------------------------------|
| Click bar icon      | Open or close the panel (word field focused)           |
| Right-click icon    | Open the words file in the Omarchy default editor (`omarchy-launch-editor`); a missing file is created empty |
| File name in header | Same as right-click: opens the words file              |
| Enter               | Capture (from the word or context field), close, toast |
| Shift+Enter         | New line in the context field (grows to 5 lines, then scrolls) |
| Esc / click outside | Close; the draft is kept for next time                 |
| Settings (gear)     | Words file (edit the path; the folder icon picks its folder and keeps the file name; the panel comes back with the name selected; "Created on first capture" shows next to MARKDOWN FILE while the path points at no file yet), clipboard prefill, languages |

- **Already captured**: while you type, the word field's border takes the
  theme's yellow (`colors.toml` `yellow`, at the field's normal border width)
  and a dim hint shows when the word is already in the file. Saving is still
  allowed. See *How matching works* below.
- **Prefill from clipboard** (Settings, off by default): choose the field it
  fills, Word (default) or Context. Opening the panel with that field empty
  fills it; text kept in the other field does not stop it. Word gets the
  clipboard's first line and the focus moves to Context; Context gets the text
  with its lines (up to 2000 characters) and the focus stays on Word. Images
  and other non-text clipboards are ignored.
- **Language** is picked from the script of the word. In Settings each
  language is one line: name, script (Latin, Cyrillic, Greek, Arabic, Hebrew,
  Any, or Custom… with a character class such as `A-Za-zÀ-ÿ`), and a remove
  button, plus up/down buttons to reorder. Order is priority:
  when several languages match the word's script, the first one in the list is
  selected. Picking one by hand sticks for the current word.
- **Errors** (no permission, path is a folder, ...) show under the Capture
  button and the panel stays open with your text.

## How matching works

**Language detection.** The word (not the context) is NFC-normalized, so a
decomposed `e` + accent counts as `é`. Then only its letters are compared:
spaces, digits, punctuation (apostrophes and hyphens: `don't`, `rock-n-roll`),
symbols, emoji and combining marks are skipped. A language matches when every
letter is in its set; a word with no letters matches none. Sets:

| Script   | Letters                                                       |
|----------|---------------------------------------------------------------|
| Latin    | A–Z, a–z, U+00C0–024F (accents, ñ, ß, …), U+1E00–1EFF (Vietnamese) |
| Cyrillic | U+0400–052F (ё included), U+1C80–1C8F, U+2DE0–2DFF, U+A640–A69F |
| Greek    | U+0370–03FF, U+1F00–1FFF                                       |
| Arabic   | U+0600–06FF, U+0750–077F, U+08A0–08FF, U+FB50–FDFF, U+FE70–FEFF |
| Hebrew   | U+0590–05FF, U+FB1D–FB4F                                       |
| Any      | every letter                                                   |
| Custom…  | your set, e.g. `A-Za-zÀ-ÿ`                                     |

A custom set is read character by character, never as a regular expression:
`x-y` is a range, a backslash escapes the next character (`\-`, `\]`, `\\`) or
spells one (`\u00e9`, `\u{1F600}`, `\x41`), and `[`, `]`, `^` are plain
characters. A broken set (a reversed range like `z-a`, a bad escape) matches
nothing; it never throws. Parsed sets are cached. When several languages
match, the first in the list wins.

**Duplicate search.** Each `- **word**` line in the file becomes a key: escapes
removed, NFC, trimmed, runs of spaces collapsed, lower-cased with the
locale-independent `toLowerCase` (so `Casa` = `casa`, `Ёж` = `ёж`). `ё` and `е`
are different words, and `ß` is not folded to `ss`. The keys sit in a hash map,
so each keystroke costs one normalization of the typed word and one lookup,
whatever the file size. A line's language for the counts is its `[Tag]`, else
the `## ` section it is in.

**When the file is read.** Never before the panel is first opened. After that
the file is watched (inotify, no polling) and re-parsed only when it changes:
about 2 ms for 1,000 entries, about 80–200 ms for 50,000. Saving does not spawn
Python: `append.sh` is plain `sh` + `awk` + `flock`.

## Files

- `WordCapture.qml` — bar button and panel, built from the shell's own
  `Panel`, `KeyboardPanel`, `PanelSectionHeader`, `PanelActionButton`,
  `Dropdown`, `Toggle`, `TextField`.
- `Model.js` — language detection and script presets, `entryLine()` (the one place that defines
  the line format), escaping, the words index (duplicates and counts per tag), clipboard cleanup.
- `append.sh` — adds one line at the end of its `## <Language>` section
  (`--touch` only creates the file):
  expands `~`, resolves relative paths against `$HOME`, follows a symlink,
  creates missing folders, writes a temp file with the original's permissions
  and renames it over the file (atomic), locks the folder (`flock`) against
  concurrent writers. Plain `sh` + `awk`, no Python start-up.
- `tests/model.test.js` — logic tests: `node tests/model.test.js`.
- `tests/append.test.sh` — file-writing tests: `sh tests/append.test.sh`.
- State: `~/.local/state/omarchy/word-capture.json` (`filePath`, `languages`,
  `language`, `prefillClipboard`, `prefillTarget`). Missing keys take their
  defaults, so older state files keep working.

## Install

Place this folder at `~/.config/omarchy/plugins/alexander.word-capture/` and
add `{ "id": "alexander.word-capture" }` to a bar section in
`~/.config/omarchy/shell.json`. After editing the QML, run
`omarchy restart shell`: the shell notices local plugin changes, but a running
shell can keep the previously compiled QML.

Requires `wl-clipboard` and Omarchy's `omarchy-file-select` (both present on
Omarchy).
