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
  const set = M.wordIndex(file)
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
    const set = M.wordIndex(M.entryLine({ text: w, note: "n_o*te", tag: "X" }))
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

test("clipboard text per target field", () => {
  assert.strictEqual(M.clipboardText(" casa\nsecond ", "word"), "casa")
  assert.strictEqual(M.clipboardText(" line one\r\nline two \n", "context"), "line one\nline two")
  assert.strictEqual(M.clipboardText("x".repeat(3000), "context").length, 2000)
  assert.strictEqual(M.clipboardText("a\u0000b", "context"), "")
})

test("detection skips non-letters", () => {
  const L = M.defaults()
  const names = (w) => Array.from(M.detect(w, L))
  assert.deepStrictEqual(names("don't"), ["English", "Spanish"])
  assert.deepStrictEqual(names("don’t"), ["English", "Spanish"])
  assert.deepStrictEqual(names("rock-n-roll"), ["English", "Spanish"])
  assert.deepStrictEqual(names("Ñandú, ¿qué?"), ["English", "Spanish"])
  assert.deepStrictEqual(names("cafe\u0301"), ["English", "Spanish"])      // NFD é
  assert.deepStrictEqual(names("ёлка"), ["Russian"])
  assert.deepStrictEqual(names("Привет 👋🏽!"), ["Russian"])
  assert.deepStrictEqual(names("2 кота"), ["Russian"])
  assert.deepStrictEqual(names("123 !!"), [])                              // no letters
  assert.deepStrictEqual(names("😀"), [])
  assert.deepStrictEqual(names("dom дом"), [])                             // mixed scripts
  assert.deepStrictEqual(names("Tiếng Việt"), ["English", "Spanish"])     // Latin Extended Additional
})

test("custom character sets are parsed safely", () => {
  const set = (c) => JSON.parse(JSON.stringify(M.parseClass(c)))
  assert.deepStrictEqual(set("A-Za-z"), [[65, 90], [97, 122]])
  assert.deepStrictEqual(set("a-"), [[97, 97], [45, 45]])
  assert.deepStrictEqual(set("\\u00e9\\x41\\u{1F600}"), [[0xe9, 0xe9], [0x41, 0x41], [0x1f600, 0x1f600]])
  assert.deepStrictEqual(set("\\]\\\\\\-"), [[93, 93], [92, 92], [45, 45]])
  assert.deepStrictEqual(set("^]["), [[94, 94], [93, 93], [91, 91]])        // no special meaning
  assert.strictEqual(set("z-a"), null)                                      // reversed range
  assert.strictEqual(set("\\u12"), null)                                    // broken escape
  assert.strictEqual(set("\\u{zz}"), null)
  assert.strictEqual(set(""), null)
  assert.ok(M.matchesCharacters("été", "a-zé"))
  assert.ok(!M.matchesCharacters("été", "z-a"))                            // invalid: matches nothing
  assert.ok(M.matchesCharacters("ab]", "ab"))                              // ] is punctuation, skipped
  assert.ok(M.matchesCharacters("гре", "а-яё"))
  assert.ok(M.matchesCharacters("anything", "any"))
  assert.ok(M.matchesCharacters("gre", "gre") && !M.matchesCharacters("greek", "gre"))
})

test("duplicate lookup normalizes Unicode and case", () => {
  const set = M.wordIndex("- **Cafe\u0301**\n- **ЁЖ**\n- **Straße**\n")
  assert.ok(M.isCaptured(set, "café"))                                     // NFD in file, NFC typed
  assert.ok(M.isCaptured(set, "ёж"))
  assert.ok(!M.isCaptured(set, "еж"))                                      // ё is not folded to е
  assert.ok(M.isCaptured(set, "STRASSE") === false)                        // no ß -> ss folding
  assert.ok(M.isCaptured(set, "straße"))
  assert.strictEqual(M.entryLine({ text: "cafe\u0301", note: "", tag: "" }), "- **caf\u00e9**\n")
})

test("index counts unique words per tag and builds the toast line", () => {
  const index = M.wordIndex([
    "# Words",
    "- **casa** [Spanish] — house",
    "- **Casa** [Spanish] — duplicate, not counted",
    "- **perro** [Spanish]",
    "- **house** [English]",
    "- **untagged**",
    "text with **bold** inside",
  ].join("\n"))
  assert.strictEqual(index.total, 4)
  assert.strictEqual(index.byTag.Spanish, 2)
  assert.strictEqual(index.byTag.English, 1)
  const fresh = M.addWord(index, M.normalizeWord("gato"), "Spanish")
  assert.deepStrictEqual(JSON.parse(JSON.stringify(fresh)), { duplicate: false, total: 5, inTag: 3 })
  assert.strictEqual(M.statsLine(fresh, "Spanish"), "5 words, 3 in Spanish")
  const again = M.addWord(index, M.normalizeWord("CASA"), "Spanish")
  assert.strictEqual(M.statsLine(again, "Spanish"), "Already had it. 5 words, 3 in Spanish")
  assert.strictEqual(M.statsLine(M.addWord(M.emptyIndex(), "w", ""), ""), "1 word")
  assert.ok(M.isCaptured(index, "gato"))
})

test("index takes the language from the tag or the section", () => {
  const file = "# Vocabulary\n- **simple** [English] — test\n- **loose**\n\n## Spanish\n\n- **casa** [Spanish]\n- **perro**\n### notes\n- **gato**\n\n## C++ (old) [x]\n- **a**\n"
  const index = M.wordIndex(file)
  assert.strictEqual(index.total, 6)
  assert.strictEqual(index.byTag["English"], 1)
  assert.strictEqual(index.byTag["Spanish"], 3)          // tag, section, and under ###
  assert.strictEqual(index.byTag["C++ (old) [x]"], 1)
  assert.strictEqual(index.words["loose"], "")
  assert.strictEqual(M.headingOf("##   Spanish  "), "Spanish")
  assert.strictEqual(M.headingOf("# Title"), "")
  assert.strictEqual(M.headingOf("### sub"), null)
  assert.strictEqual(M.headingOf("#hashtag"), null)
})

test("nameRange selects the file name without its extension", () => {
  const sel = p => { const r = M.nameRange(p); return p.slice(r[0], r[1]) }
  assert.strictEqual(sel("~/Documents/words.md"), "words")
  assert.strictEqual(sel("/a.b/notes"), "notes")
  assert.strictEqual(sel("/x/.vocab"), ".vocab")
  assert.strictEqual(sel("/x/my.words.txt"), "my.words")
  assert.strictEqual(sel("/x/"), "")
})

test("prefill fills only an empty target field", () => {
  assert.strictEqual(M.prefillField("word", "", ""), "word")
  assert.strictEqual(M.prefillField("word", "casa", ""), "")
  assert.strictEqual(M.prefillField("word", " ", "kept note"), "word")
  assert.strictEqual(M.prefillField("context", "kept word", ""), "context")
  assert.strictEqual(M.prefillField("context", "", "note"), "")
  assert.strictEqual(M.prefillField("other", "", ""), "word")
})

test("toast says Already had it only for a word captured before the save", () => {
  const file = "## Spanish\n\n- **casa** [Spanish]\n"
  // New word, index not yet re-read: no duplicate, counts go up.
  let index = M.wordIndex(file)
  let was = M.isCaptured(index, "perro")
  assert.strictEqual(M.statsLine(M.recordCapture(index, M.normalizeWord("perro"), "Spanish", was), "Spanish"), "2 words, 2 in Spanish")
  // New word, the file watch re-read the file (new line included) first: still new.
  index = M.wordIndex(file)
  was = M.isCaptured(index, "perro")
  const reread = M.wordIndex(file + "- **perro** [Spanish]\n")
  assert.strictEqual(M.statsLine(M.recordCapture(reread, M.normalizeWord("perro"), "Spanish", was), "Spanish"), "2 words, 2 in Spanish")
  // Existing word: Already had it, counts unchanged.
  index = M.wordIndex(file)
  was = M.isCaptured(index, "Casa")
  assert.strictEqual(M.statsLine(M.recordCapture(index, M.normalizeWord("Casa"), "Spanish", was), "Spanish"), "Already had it. 1 word, 1 in Spanish")
})

console.log(passed + " passed")
