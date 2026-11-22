# Word Capture

An Omarchy bar widget for collecting vocabulary. Click the book icon, type a
word, optionally add context, press Enter. One Markdown line is appended to
your vocabulary file:

```markdown
- **casa** [Spanish] — la casa es grande
```

## Use

| Key / action       | Does                                        |
|--------------------|---------------------------------------------|
| Click bar icon     | Open or close the panel (word field focused) |
| Enter              | Capture (from the word or context field)     |
| Esc                | Close                                        |
| SETTINGS           | Vocabulary file and languages                |

The language is picked from the characters in the word: each language has a
character class (`latin`, `cyrillic`, `greek`, `arabic`, `hebrew`, `any`, or a
custom class such as `A-Za-zÀ-ÿ`). When several languages match, the panel
keeps the one you last picked.

If a write fails (no permission, path is a folder, ...), the reason is shown
under the Capture button and the panel stays open with your text.

## Files

- `WordCapture.qml` — bar button and panel (shell `Panel`, `KeyboardPanel`).
- `Model.js` — language detection and `entryLine()`, the one place that
  defines the Markdown line format.
- `append.py` — appends one line: creates missing folders, expands `~`,
  resolves relative paths against `$HOME`, adds a newline if the file lacks
  one, and locks the file while writing.
- State: `~/.local/state/omarchy/word-capture.json` (file path, languages,
  last language).

## Install

Place this folder at `~/.config/omarchy/plugins/alexander.word-capture/` and
add `{ "id": "alexander.word-capture" }` to a bar section in
`~/.config/omarchy/shell.json`. The shell reloads local plugins on change;
`omarchy restart shell` forces a full reload.

Requires `python3` (present on Omarchy).
