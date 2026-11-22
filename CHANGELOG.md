# Changelog

## 1.4.3

- In Settings, the "Settings" subtitle no longer shows a link cursor; the
  file-name link exists only in the main view.

## 1.4.2

- The clipboard option's description is shorter and stays on one line, and
  the row keeps the same height for Word and Context.

## 1.4.1

- The clipboard option's description names the field it fills (word or
  context) instead of always saying "word".

## 1.4.0

- Ready to publish: end-user README, this changelog, `sh tests/run.sh`.
- Settings follow `XDG_STATE_HOME`.
- Plugin id is now `lipionix.word-capture` (was `alexander.word-capture`);
  repository `github.com/lipionix/omarchy-word-capture`.
- MIT license.

## 1.3.x

- Entries go under a `## <Language>` heading, at the end of that section; a
  missing section is added at the end of the file.
- One folder button for the words file. The panel reopens in Settings
  afterwards with the file name selected.
- "Created on first capture" next to MARKDOWN FILE when the file does not
  exist yet; the header shows "(new)".
- Click a matching language name to pick it.
- Click the file name in the header, or the notification, to open the file.
- The notification shows word counts ("128 words, 42 in Spanish").
- Clipboard prefill fills only its empty target field and moves the cursor
  to the other field.
- Fixed: "Already had it" on every new word; the yellow duplicate border
  being too faint; the context field showing two lines for one.
- Faster language matching and duplicate index; saving uses `sh` instead
  of Python; nothing is read until the panel is first opened.

## 1.2.0

- Yellow word-field border while the word is already in the file.
- Up and down arrows set language priority.
- Multi-line context field (Shift+Enter).
- Choose whether the clipboard fills Word or Context.

## 1.1.x

- Notification after saving; right-click opens the words file.
- "Already captured" hint while typing.
- Optional prefill from the clipboard.
- One-line language rows with an alphabet dropdown.
- Markdown characters in entries are escaped.

## 1.0.x

- First version: capture a word, context and language into a Markdown file.
- Safe saving (lock, atomic write), errors shown in the panel, focus on open,
  Enter to save.
