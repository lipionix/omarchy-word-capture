# Word Capture

An Omarchy bar widget for collecting vocabulary. Click the book icon, type a
word, optionally add context, press Enter. One Markdown line is appended to
your vocabulary file and a toast confirms it:

```markdown
- **casa** [Spanish] — la casa es grande
```

`\`, `*` and `_` in the word and the context are backslash-escaped, so
`snake_case` or `**x**` cannot break the bold word.

## Use

| Key / action        | Does                                                   |
|---------------------|--------------------------------------------------------|
| Click bar icon      | Open or close the panel (word field focused)           |
| Right-click icon    | Open the words file in the Omarchy default editor (`omarchy-launch-editor`); a missing file is created empty |
| Enter               | Capture (from the word or context field), close, toast |
| Esc / click outside | Close; the draft is kept for next time                 |
| Settings (gear)     | Words file, clipboard prefill, languages               |

- **Already captured**: while you type, a dim hint shows when the word is
  already in the file (case-insensitive, compared on the `**word**` part).
  Saving is still allowed. The file is watched, so edits made elsewhere count.
- **Prefill from clipboard** (Settings, off by default): opening the panel with
  an empty word field puts the clipboard's first line into it, selected, so
  typing replaces it. Images and other non-text clipboards are ignored.
- **Language** is picked from the script of the word. In Settings each
  language is one line: name, script (Latin, Cyrillic, Greek, Arabic, Hebrew,
  Any, or Custom… with a character class such as `A-Za-zÀ-ÿ`), and a remove
  button. When several languages match, the one you last picked stays.
- **Errors** (no permission, path is a folder, ...) show under the Capture
  button and the panel stays open with your text.

## Files

- `WordCapture.qml` — bar button and panel, built from the shell's own
  `Panel`, `KeyboardPanel`, `PanelHero`, `PanelSectionHeader`, `Toggle`.
- `Model.js` — language detection and script presets, `entryLine()` (the one place that defines
  the line format), escaping, duplicate parsing, clipboard cleanup.
- `append.py` — appends one line (or `--touch` to only create the file):
  creates missing folders, expands `~`, resolves relative paths against
  `$HOME`, adds a newline if the file lacks one, locks the file while writing.
- `tests/model.test.js` — logic tests: `node tests/model.test.js`.
- State: `~/.local/state/omarchy/word-capture.json` (`filePath`, `languages`,
  `language`, `prefillClipboard`).

## Install

Place this folder at `~/.config/omarchy/plugins/alexander.word-capture/` and
add `{ "id": "alexander.word-capture" }` to a bar section in
`~/.config/omarchy/shell.json`. After editing the QML, run
`omarchy restart shell`: the shell notices local plugin changes, but a running
shell can keep the previously compiled QML.

Requires `python3` and `wl-clipboard` (both present on Omarchy).
