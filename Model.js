function safeText(value, limit) {
  return String(value || "").replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/g, "").slice(0, limit)
}

function defaults() {
  return [
    { name: "English", characters: "latin" },
    { name: "Spanish", characters: "latin" },
    { name: "Russian", characters: "cyrillic" }
  ]
}

function validCharacters(value) {
  var characters = safeText(value, 160).trim()
  return characters || "any"
}

function normalizeLanguages(value) {
  var source = Array.isArray(value) ? value : defaults()
  var out = []
  for (var i = 0; i < source.length && out.length < 20; i++) {
    var name = safeText(source[i] && source[i].name, 40).trim()
    if (!name) continue
    // `charset` is the legacy key; accept it so existing state still loads.
    var characters = source[i] && (source[i].characters || source[i].charset)
    out.push({ name: name, characters: validCharacters(characters) })
  }
  return out.length ? out : defaults()
}

// ---- Script detection -------------------------------------------------------
// A word matches a language when every letter in it belongs to that language's
// character set. Spaces, digits, punctuation (apostrophes, hyphens), symbols,
// emoji and combining marks are not letters and are skipped; a word with no
// letters at all matches nothing. Text is NFC-normalized first, so a decomposed
// "e + U+0301" counts as "é". Sets are lists of code-point ranges; a custom set
// is parsed by hand (never handed to RegExp), so no input can break it.

var presetRanges = {
  latin: [[0x41, 0x5a], [0x61, 0x7a], [0xc0, 0x24f], [0x1e00, 0x1eff]],
  cyrillic: [[0x400, 0x52f], [0x1c80, 0x1c8f], [0x2de0, 0x2dff], [0xa640, 0xa69f]],
  greek: [[0x370, 0x3ff], [0x1f00, 0x1fff]],
  arabic: [[0x600, 0x6ff], [0x750, 0x77f], [0x8a0, 0x8ff], [0xfb50, 0xfdff], [0xfe70, 0xfeff]],
  hebrew: [[0x590, 0x5ff], [0xfb1d, 0xfb4f]]
}

// Never letters: controls and spaces, ASCII and Latin-1 punctuation, digits and
// symbols (× ÷ too), spacing modifiers (ʼ), combining marks, general and
// supplemental punctuation, currency, arrows/math/shapes/dingbats, CJK
// punctuation, variation selectors, full-width ASCII punctuation, emoji, tags.
var skipRanges = [
  [0x0, 0x40], [0x5b, 0x60], [0x7b, 0xbf], [0xd7, 0xd7], [0xf7, 0xf7],
  [0x2b0, 0x36f], [0x1ab0, 0x1aff], [0x1dc0, 0x1dff],
  [0x2000, 0x2bff], [0x2e00, 0x2e7f], [0x3000, 0x303f],
  [0xfe00, 0xfe2f], [0xfeff, 0xfeff], [0xff01, 0xff20], [0xff3b, 0xff40], [0xff5b, 0xff65],
  [0x1f000, 0x1faff], [0xe0000, 0xe007f]
]

function inRanges(cp, ranges) {
  for (var i = 0; i < ranges.length; i++)
    if (cp >= ranges[i][0] && cp <= ranges[i][1]) return true
  return false
}

// "A-Za-zÀ-ÿ" -> ranges. Every character stands for itself, "x-y" is a range,
// and a backslash escapes the next character (\- \] \\ \^) or spells one
// (\u00e9, \u{1f600}, \x41). [ ] ^ have no special meaning. Returns null when
// the text is not a valid set (a reversed range, a broken escape, empty).
function parseClass(text) {
  var src = String(text || "")
  var i = 0
  function atom() {
    if (i >= src.length) return -1
    var cp = src.codePointAt(i)
    i += cp > 0xffff ? 2 : 1
    if (cp !== 0x5c) return cp
    if (i >= src.length) return -1
    var next = src.charAt(i)
    var hex = null
    if (next === "u" && src.charAt(i + 1) === "{") {
      var close = src.indexOf("}", i + 2)
      if (close < 0) return -1
      hex = src.slice(i + 2, close); i = close + 1
    } else if (next === "u") {
      hex = src.slice(i + 1, i + 5); i += 5; if (hex.length !== 4) return -1
    } else if (next === "x") {
      hex = src.slice(i + 1, i + 3); i += 3; if (hex.length !== 2) return -1
    }
    if (hex !== null) {
      if (!/^[0-9A-Fa-f]{1,6}$/.test(hex)) return -1
      var value = parseInt(hex, 16)
      return value <= 0x10ffff ? value : -1
    }
    cp = src.codePointAt(i)
    i += cp > 0xffff ? 2 : 1
    return cp
  }
  var ranges = []
  while (i < src.length) {
    var lo = atom()
    if (lo < 0) return null
    var hi = lo
    if (src.charAt(i) === "-" && i + 1 < src.length) {
      i++
      hi = atom()
      if (hi < 0 || hi < lo) return null
    }
    ranges.push([lo, hi])
  }
  return ranges.length ? ranges : null
}

// Parsed sets, by their text: parsing happens once, not per keystroke.
var classCache = {}

// "any" -> true (every letter), preset -> its ranges, custom -> parsed
// ranges, invalid custom -> null (matches nothing).
function characterSet(characters) {
  var key = String(characters || "")
  if (Object.prototype.hasOwnProperty.call(classCache, key)) return classCache[key]
  var lower = key.trim().toLowerCase()
  var set = lower === "any" ? true : (presetRanges[lower] || parseClass(key))
  classCache[key] = set
  return set
}

// NFC only matters past ASCII; skipping it there keeps the common case cheap.
function nfc(value) {
  var s = String(value || "")
  return /[^\x00-\x7f]/.test(s) && typeof s.normalize === "function" ? s.normalize("NFC") : s
}

// The letters of a text, as code points (astral characters stay whole).
function letters(text) {
  var value = nfc(safeText(text, 3000))
  var out = []
  for (var i = 0; i < value.length;) {
    var cp = value.codePointAt(i)
    i += cp > 0xffff ? 2 : 1
    if (cp < 0x80) {
      // ASCII fast path: only A-Z and a-z are letters.
      if ((cp >= 0x41 && cp <= 0x5a) || (cp >= 0x61 && cp <= 0x7a)) out.push(cp)
    } else if (!inRanges(cp, skipRanges)) out.push(cp)
  }
  return out
}

function matchesLetters(cps, characters) {
  if (!cps.length) return false
  var set = characterSet(characters)
  if (set === true) return true
  if (!set) return false
  for (var i = 0; i < cps.length; i++)
    if (!inRanges(cps[i], set)) return false
  return true
}

function matchesCharacters(text, characters) {
  return matchesLetters(letters(text), characters)
}

// Matching languages in list order: the list order is the priority.
function detect(text, languages) {
  var cps = letters(text)
  var result = []
  if (!cps.length) return result
  var list = normalizeLanguages(languages)
  for (var i = 0; i < list.length; i++)
    if (matchesLetters(cps, list[i].characters)) result.push(list[i].name)
  return result
}

// The script choices in Settings. Each maps to a characters value in state;
// any other value is a custom character class.
var scriptPresets = [
  { label: "Latin", value: "latin" },
  { label: "Cyrillic", value: "cyrillic" },
  { label: "Greek", value: "greek" },
  { label: "Arabic", value: "arabic" },
  { label: "Hebrew", value: "hebrew" },
  { label: "Any", value: "any" }
]
var customScript = "Custom…"

function scriptLabels() {
  return scriptPresets.map(function(item) { return item.label }).concat([customScript])
}

// "cyrillic" -> "Cyrillic"; "A-Za-zÀ-ÿ" -> "Custom…".
function scriptLabel(characters) {
  var value = String(characters || "").trim().toLowerCase()
  for (var i = 0; i < scriptPresets.length; i++)
    if (scriptPresets[i].value === value) return scriptPresets[i].label
  return customScript
}

// The characters value to store for a picked label; "" for Custom…, whose
// class comes from its own field.
function scriptValue(label) {
  for (var i = 0; i < scriptPresets.length; i++)
    if (scriptPresets[i].label === label) return scriptPresets[i].value
  return ""
}

// Same rule as append.sh: "~" is home, and a relative path is under home.
function resolvePath(path, home) {
  var p = String(path || "").trim()
  if (!p) return ""
  if (p === "~") return home
  if (p.indexOf("~/") === 0) return home + p.slice(1)
  return p.charAt(0) === "/" ? p : home + "/" + p
}

// How two captures compare: escapes removed, NFC, trimmed, single-spaced,
// lower-cased with the locale-independent toLowerCase. ё and е stay different.
function normalizeWord(value) {
  return keyOf(nfc(unescapeMarkdown(value)))
}

// normalizeWord for text that is already NFC (the whole file is normalized once).
function keyOf(value) {
  return unescapeMarkdown(value).trim().replace(/\s+/g, " ").toLowerCase()
}

// The words file as an index: every "- **word** [Tag]" line, by normalized
// word (first occurrence wins), with unique-word counts in total and per tag.
// Lines that are not captures (headings, notes) are skipped. Lookups are a
// hash hit, so the per-keystroke cost does not grow with the file.
function emptyIndex() {
  return { words: {}, total: 0, byTag: {} }
}

function wordIndex(text) {
  var index = emptyIndex()
  // One NFC pass over the whole file is far cheaper than one per line.
  var lines = nfc(text).split("\n")
  var pattern = /^\s*[-*+]\s+\*\*((?:\\.|[^\\*])+)\*\*(?:\s*\[([^\]\n]*)\])?/
  // The language of a line is its [Tag], else the "## " section it sits in.
  var section = ""
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    var h = line.charAt(0) === "#" ? headingOf(line) : null
    if (h !== null) { section = h; continue }
    // Cheap pre-check before the regex: a capture line has "**" early on.
    if (line.indexOf("**") < 0) continue
    var match = pattern.exec(line)
    if (match) addWord(index, keyOf(match[1]), match[2] || section)
  }
  return index
}

// "## Spanish" -> "Spanish"; "# Title" and "##" without a name -> ""
// (outside any section); anything else (including "### sub") -> null, not a
// section boundary.
function headingOf(line) {
  var m = /^(#{1,2})(?:[ \t]+(.*?))?[ \t]*\r?$/.exec(line)
  if (!m) return null
  return m[1] === "##" ? (m[2] || "") : ""
}

// How section and tag names compare: case of A-Z and runs of spaces ignored,
// exactly as append.sh matches "## " headings, so "## spanish" and [Spanish]
// count as one language.
function sectionKey(name) {
  return String(name || "").replace(/^[ \t\r]+|[ \t\r]+$/g, "").replace(/[ \t]+/g, " ")
    .replace(/[A-Z]/g, function(c) { return c.toLowerCase() })
}

// Record one word; returns { duplicate, total, inTag } after the change.
function addWord(index, key, tag) {
  var name = String(tag || "").trim()
  var group = sectionKey(name)
  var duplicate = key === "" || Object.prototype.hasOwnProperty.call(index.words, key)
  if (!duplicate) {
    index.words[key] = name
    index.total++
    if (group) index.byTag[group] = (index.byTag[group] || 0) + 1
  }
  return { duplicate: duplicate, total: index.total, inTag: group ? (index.byTag[group] || 0) : 0 }
}

function isCaptured(index, word) {
  var key = normalizeWord(word)
  return key !== "" && !!index && !!index.words && Object.prototype.hasOwnProperty.call(index.words, key)
}

// Count a saved word for the toast. "duplicate" comes from wasCaptured, the
// check made before the write: the file watch can re-read the file (new line
// included) before the save reports back, so the index alone cannot tell.
function recordCapture(index, key, tag, wasCaptured) {
  var result = addWord(index, key, tag)
  result.duplicate = !!wasCaptured
  return result
}

// The toast line after a save: "128 words, 42 in Spanish", led by
// "Already had it." when the word was in the file before.
function statsLine(result, tag) {
  var text = result.total + (result.total === 1 ? " word" : " words")
  var name = String(tag || "").trim()
  if (name) text += ", " + result.inTag + " in " + name
  return (result.duplicate ? "Already had it. " : "") + text
}

// Which field the clipboard prefill fills: the target, only while it is
// empty; the other field never blocks it. "" means fill nothing.
function prefillField(target, word, context) {
  var field = target === "context" ? "context" : "word"
  var current = field === "context" ? context : word
  return String(current || "").trim() ? "" : field
}

// Clipboard text worth prefilling: the first non-empty line, single-spaced,
// capped. Anything that looks binary (NUL or replacement characters) is "".
function clipboardWord(raw) {
  var text = String(raw || "")
  if (/[\u0000\ufffd]/.test(text)) return ""
  var lines = text.split(/\r?\n/)
  for (var i = 0; i < lines.length; i++) {
    var line = safeText(lines[i], 4000).replace(/\s+/g, " ").trim()
    if (line) return line.slice(0, 120).trim()
  }
  return ""
}

// Clipboard text for the chosen field: the word takes one line (above); the
// context keeps its lines, capped at 2000 characters. Binary gives "".
function clipboardText(raw, target) {
  if (target !== "context") return clipboardWord(raw)
  var text = String(raw || "")
  if (/[\u0000\ufffd]/.test(text)) return ""
  return safeText(text.replace(/\r\n?/g, "\n"), 2000).trim()
}

// [start, end) of the file name in a path, without its extension, for
// selecting it ("~/notes/words.md" -> the "words"). Dotfiles keep their dot.
function nameRange(path) {
  var text = String(path || "")
  var start = text.lastIndexOf("/") + 1
  var dot = text.lastIndexOf(".")
  var end = dot > start ? dot : text.length
  return [start, end]
}

// "~/Documents/word.md" -> "word.md", for the panel's meta line.
function fileName(path) {
  var parts = String(path || "").trim().split("/")
  return parts[parts.length - 1] || ""
}

// Backslash-escape what would turn part of a capture into Markdown emphasis
// (or into an escape itself): \ * _. Everything else stays readable as typed.
function escapeMarkdown(value) {
  return String(value || "").replace(/[\\*_]/g, "\\$&")
}

function unescapeMarkdown(value) {
  return String(value || "").replace(/\\([\\`*_{}\[\]()#+\-.!|<>~])/g, "$1")
}

// The one place that decides how a capture looks in the Markdown file:
// "- **text** [tag] — note", always a single line. Takes named fields so the format can change
// without touching the panel or the writer (append.sh).
function entryLine(fields) {
  var text = escapeMarkdown(nfc(safeText(fields.text, 500)).trim().replace(/\s*\r?\n\s*/g, " "))
  // A multi-line note stays one list line: its lines are joined with " / ".
  var note = escapeMarkdown(nfc(safeText(fields.note, 2000)).split(/\r?\n/)
    .map(function(line) { return line.trim() })
    .filter(function(line) { return line !== "" })
    .join(" / "))
  var tag = safeText(fields.tag, 80).trim()
  return "- **" + text + "**" + (tag ? " [" + tag + "]" : "") + (note ? " — " + note : "") + "\n"
}
