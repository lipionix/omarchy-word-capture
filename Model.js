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

function charactersPattern(characters) {
  var builtIn = {
    latin: "A-Za-z\\u00c0-\\u024f",
    cyrillic: "\\u0400-\\u052f",
    greek: "\\u0370-\\u03ff",
    arabic: "\\u0600-\\u06ff",
    hebrew: "\\u0590-\\u05ff"
  }
  return builtIn[String(characters).toLowerCase()] || String(characters)
}

function matchesCharacters(text, characters) {
  var value = safeText(text, 3000)
  if (!value.trim()) return false
  if (String(characters).toLowerCase() === "any") return true
  var pattern
  try { pattern = new RegExp("[" + charactersPattern(characters) + "]") } catch (e) { return false }
  for (var i = 0; i < value.length; i++) {
    var ch = value[i]
    if (/\s|[0-9\u2000-\u206f\u2e00-\u2e7f]/.test(ch)) continue
    if (!pattern.test(ch)) return false
  }
  return true
}

function detect(text, languages) {
  var result = []
  var list = normalizeLanguages(languages)
  for (var i = 0; i < list.length; i++) {
    if (matchesCharacters(text, list[i].characters)) result.push(list[i].name)
  }
  return result
}

var characterPresets = ["latin", "cyrillic", "greek", "arabic", "hebrew", "any"]

function characterSuggestions(text) {
  var query = safeText(text, 40).trim().toLowerCase()
  if (!query) return characterPresets
  return characterPresets.filter(function(name) { return name.indexOf(query) !== -1 })
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
// "- **text** [tag] — note". Takes named fields so the format can change
// without touching the panel or the writer (append.py).
function entryLine(fields) {
  var text = escapeMarkdown(safeText(fields.text, 500).trim().replace(/\s*\r?\n\s*/g, " "))
  var note = escapeMarkdown(safeText(fields.note, 2000).trim().replace(/\s*\r?\n\s*/g, " "))
  var tag = safeText(fields.tag, 80).trim()
  return "- **" + text + "**" + (tag ? " [" + tag + "]" : "") + (note ? " — " + note : "") + "\n"
}
