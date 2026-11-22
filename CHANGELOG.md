# Changelog

## 1.6.0

- Saving writes into the same file instead of replacing it with a new one,
  so the file always keeps its owner, group, permissions and access list
  (ACL). The attribute copying and checks of 1.5.2 to 1.5.4 are gone.
- A words file the plugin creates is readable only by you (0600).
- A save starts two small programs (`flock`, `awk`) and no temporary file.
- Trade-off: the save is no longer an atomic swap. If the write is cut off
  (power loss, full disk), the file can be left truncated.

## 1.5.4

- Saving keeps the words file's owner and group. In a shared folder where the
  replacement file could not get them, the entry is written into the existing
  file instead, so a save never gives another group access to the notes.

## 1.5.3

- An existing `## Language` heading is found whatever the case of A to Z and
  the spacing, and kept as written, so `## spanish` no longer gets a second
  Spanish section. The notification counts agree.
- Files with Windows (CRLF) line endings keep them on new lines.
- Tests rewritten around what users see; `sh tests/run.sh` prints one summary
  line. The program count moved to an optional `sh tests/perf.sh`.

## 1.5.2

- Saving keeps the words file's access list (POSIX ACL), owner and group
  where allowed, not only its mode bits, so a save never widens who can read
  the file. If an ACL cannot be kept, the save stops with an error instead.
- The save notification names the word that was submitted, even if the
  field changed while it was being written.

## 1.5.1

- Moving a language up or down slides the row to its new place, so it is easy
  to follow. The row keeps its controls, so a focused arrow can be pressed
  again. No animation when Omarchy's animations are off.

## 1.5.0

- Lighter: the bar holds only the icon until the first click, which creates
  the panel (`Panel.qml`); Settings are built when first opened.
- The words file is parsed once after a save, and the language hints are
  rebuilt only when they change.
- A save runs six programs instead of twelve.
- Already captured words are marked in the theme's urgent color, which the
  shell uses for warnings; `colors.toml` is no longer read.

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
