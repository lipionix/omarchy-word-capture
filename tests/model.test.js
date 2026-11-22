// Logic tests for Model.js: node tests/model.test.js
// Model.js is a QML JavaScript resource (no exports), so load it into a context.
const fs = require("fs")
const vm = require("vm")
const path = require("path")
const assert = require("assert")

const M = {}
vm.createContext(M)
vm.runInContext(fs.readFileSync(path.join(__dirname, "..", "Model.js"), "utf8"), M)

let passed = 0
function test(name, fn) { fn(); passed++ }

test("entry line keeps the format", () => {
  assert.strictEqual(M.entryLine({ text: " casa ", note: "la casa", tag: "Spanish" }), "- **casa** [Spanish] — la casa\n")
  assert.strictEqual(M.entryLine({ text: "w", note: "", tag: "" }), "- **w**\n")
})

test("escapes emphasis characters in word and note", () => {
  assert.strictEqual(M.entryLine({ text: "snake_case **x**", note: "a*b_c \\ d", tag: "English" }),
    "- **snake\\_case \\*\\*x\\*\\*** [English] — a\\*b\\_c \\\\ d\n")
})

test("flattens newlines (note lines join with / )", () => {
  assert.strictEqual(M.entryLine({ text: "a\nb", note: "c\r\n d", tag: "" }), "- **a b** — c / d\n")
  assert.strictEqual(M.entryLine({ text: "w", note: "line one\n\n  line_two  \n", tag: "X" }), "- **w** [X] — line one / line\\_two\n")
})

test("escape round-trips", () => {
  for (const s of ["snake_case", "**x**", "a\\b", "plain", "a\\*b"])
    assert.strictEqual(M.unescapeMarkdown(M.escapeMarkdown(s)), s)
})

test("detects by script", () => {
  assert.deepStrictEqual(Array.from(M.detect("привет", M.defaults())), ["Russian"])
  assert.deepStrictEqual(Array.from(M.detect("hola", M.defaults())), ["English", "Spanish"])
})

test("file name for the meta line", () => {
  assert.strictEqual(M.fileName("/home/a/Documents/word.md"), "word.md")
  assert.strictEqual(M.fileName("~/notes.md"), "notes.md")
  assert.strictEqual(M.fileName(""), "")
})

test("parses captured words from the file", () => {
  const file = [
    "# Vocabulary",
    "- **Casa** [Spanish] — la casa",
    "- **snake\\_case** [English]",
    "- **\\*\\*x\\*\\*** [English] — escaped stars",
    "  * **Привет**  [Russian]",
    "Some prose with **bold** text",
    "- **two  words**",
    "",
  ].join("\n")
  const set = M.capturedWords(file)
  assert.ok(M.isCaptured(set, "casa"))
  assert.ok(M.isCaptured(set, "  CASA "))
  assert.ok(M.isCaptured(set, "snake_case"))
  assert.ok(M.isCaptured(set, "**x**"))
  assert.ok(M.isCaptured(set, "привет"))
  assert.ok(M.isCaptured(set, "two words"))
  assert.ok(!M.isCaptured(set, "bold"))
  assert.ok(!M.isCaptured(set, "vocabulary"))
  assert.ok(!M.isCaptured(set, ""))
})

test("a written line is found again", () => {
  for (const w of ["snake_case", "a*b", "back\\slash", "Ñandú", "two words"]) {
    const set = M.capturedWords(M.entryLine({ text: w, note: "n_o*te", tag: "X" }))
    assert.ok(M.isCaptured(set, w), w)
  }
})

test("resolves paths like append.py", () => {
  assert.strictEqual(M.resolvePath("~/Documents/word.md", "/home/a"), "/home/a/Documents/word.md")
  assert.strictEqual(M.resolvePath("notes/w.md", "/home/a"), "/home/a/notes/w.md")
  assert.strictEqual(M.resolvePath("/tmp/w.md", "/home/a"), "/tmp/w.md")
  assert.strictEqual(M.resolvePath(" ", "/home/a"), "")
})

test("clipboard prefill text", () => {
  assert.strictEqual(M.clipboardWord("  casa \n"), "casa")
  assert.strictEqual(M.clipboardWord("\n\n first  line \nsecond"), "first line")
  assert.strictEqual(M.clipboardWord("a\u0000b"), "")
  assert.strictEqual(M.clipboardWord("\ufffdPNG"), "")
  assert.strictEqual(M.clipboardWord(""), "")
  assert.strictEqual(M.clipboardWord("x".repeat(500)).length, 120)
})

test("script presets map to dropdown items", () => {
  assert.strictEqual(M.scriptLabel("cyrillic"), "Cyrillic")
  assert.strictEqual(M.scriptLabel("Latin"), "Latin")
  assert.strictEqual(M.scriptLabel("any"), "Any")
  assert.strictEqual(M.scriptLabel("A-Za-zÀ-ÿ"), "Custom…")
  assert.strictEqual(M.scriptLabel(""), "Custom…")
  assert.strictEqual(M.scriptValue("Greek"), "greek")
  assert.strictEqual(M.scriptValue("Custom…"), "")
  assert.deepStrictEqual(Array.from(M.scriptLabels()), ["Latin", "Cyrillic", "Greek", "Arabic", "Hebrew", "Any", "Custom…"])
  for (const label of M.scriptLabels().slice(0, -1))
    assert.strictEqual(M.scriptLabel(M.scriptValue(label)), label)
})

test("a custom class still detects", () => {
  const langs = [{ name: "French", characters: "A-Za-zÀ-ÿ" }, { name: "Russian", characters: "cyrillic" }]
  assert.deepStrictEqual(Array.from(M.detect("été", langs)), ["French"])
})

test("theme yellow from colors.toml", () => {
  assert.strictEqual(M.themeYellow('accent = "#ff9f0a"\nyellow = "#ffc27a"\nbright_yellow = "#ffd8a8"\n'), "#ffc27a")
  assert.strictEqual(M.themeYellow('color3 = "#e5c07b"\n'), "#e5c07b")
  assert.strictEqual(M.themeYellow('color3="#111111"\nyellow="#222222"'), "#222222")
  assert.strictEqual(M.themeYellow(""), "")
})

test("matches follow list order (priority)", () => {
  const langs = [{ name: "Spanish", characters: "latin" }, { name: "English", characters: "latin" }, { name: "Russian", characters: "cyrillic" }]
  assert.deepStrictEqual(Array.from(M.detect("casa", langs)), ["Spanish", "English"])
  assert.deepStrictEqual(Array.from(M.normalizeLanguages(langs)).map(l => l.name), ["Spanish", "English", "Russian"])
})

console.log(passed + " passed")
