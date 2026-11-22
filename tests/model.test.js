// Tests for Model.js, the panel's logic: node tests/model.test.js
// Model.js is a QML JavaScript resource (no exports), so it is loaded into a
// context. The last line is a summary that tests/run.sh reads.
const fs = require("fs")
const os = require("os")
const vm = require("vm")
const path = require("path")
const nodeAssert = require("assert")
const { execFileSync } = require("child_process")

const root = path.join(__dirname, "..")
const M = {}
vm.createContext(M)
vm.runInContext(fs.readFileSync(path.join(root, "Model.js"), "utf8"), M)

// Every check goes through `assert`, which counts it; a test that makes no
// check fails, so a test cannot pass by doing nothing.
let checks = 0
const assert = {}
for (const key of ["ok", "strictEqual", "deepStrictEqual", "notStrictEqual"])
  assert[key] = (...args) => { checks++; return nodeAssert[key](...args) }

let passed = 0, failed = 0
function test(name, fn) {
  checks = 0
  try {
    fn()
    if (!checks) throw new Error("made no checks")
    passed++
  } catch (e) {
    failed++
    console.log("FAIL: " + name + "\n" + String(e.message || e).replace(/^/gm, "    "))
  }
}

const list = (value) => Array.from(value)
const detect = (word, languages) => list(M.detect(word, languages || M.defaults()))
// The toast line after capturing `word` in `tag` into a file with this text.
const statsAfter = (file, word, tag) =>
  M.statsLine(M.recordCapture(M.wordIndex(file), M.normalizeWord(word), tag, M.isCaptured(M.wordIndex(file), word)), tag)

// Run append.sh in a scratch HOME; returns its stdout. Removed afterwards.
function withScratch(fn) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "wc-test-"))
  try { return fn(dir) } finally { fs.rmSync(dir, { recursive: true, force: true }) }
}
const append = (home, ...args) =>
  execFileSync("sh", [path.join(root, "append.sh"), ...args], { env: { ...process.env, HOME: home } }).toString().trim()

// ---- The entry line -----------------------------------------------------------

test("entry line format", () => {
  assert.strictEqual(M.entryLine({ text: " casa ", note: "la casa", tag: "Spanish" }), "- **casa** [Spanish] — la casa\n")
  assert.strictEqual(M.entryLine({ text: "w", note: "", tag: "" }), "- **w**\n")
})

test("* _ and \\ are escaped in the word and the note", () => {
  assert.strictEqual(M.entryLine({ text: "snake_case **x**", note: "a*b_c \\ d", tag: "English" }),
    "- **snake\\_case \\*\\*x\\*\\*** [English] — a\\*b\\_c \\\\ d\n")
})

test("note lines are joined with ' / ', word lines with a space", () => {
  assert.strictEqual(M.entryLine({ text: "a\nb", note: "c\r\n d", tag: "" }), "- **a b** — c / d\n")
  assert.strictEqual(M.entryLine({ text: "w", note: "line one\n\n  line_two  \n", tag: "X" }), "- **w** [X] — line one / line\\_two\n")
})

// ---- Language detection ---------------------------------------------------------

test("the alphabet picks the language", () => {
  assert.deepStrictEqual(detect("привет"), ["Russian"])
  assert.deepStrictEqual(detect("hola"), ["English", "Spanish"])
})

test("only letters count", () => {
  assert.deepStrictEqual(detect("don't"), ["English", "Spanish"])
  assert.deepStrictEqual(detect("don’t"), ["English", "Spanish"])
  assert.deepStrictEqual(detect("rock-n-roll"), ["English", "Spanish"])
  assert.deepStrictEqual(detect("Ñandú, ¿qué?"), ["English", "Spanish"])
  assert.deepStrictEqual(detect("cafe\u0301"), ["English", "Spanish"])      // decomposed é
  assert.deepStrictEqual(detect("ёлка"), ["Russian"])
  assert.deepStrictEqual(detect("Привет 👋🏽!"), ["Russian"])
  assert.deepStrictEqual(detect("2 кота"), ["Russian"])
  assert.deepStrictEqual(detect("Tiếng Việt"), ["English", "Spanish"])
  assert.deepStrictEqual(detect("123 !!"), [])                              // no letters
  assert.deepStrictEqual(detect("😀"), [])
  assert.deepStrictEqual(detect(""), [])
  assert.deepStrictEqual(detect("dom дом"), [])                             // two alphabets
})

test("list order is priority", () => {
  const spanishFirst = [{ name: "Spanish", characters: "latin" }, { name: "English", characters: "latin" }, { name: "Russian", characters: "cyrillic" }]
  assert.deepStrictEqual(detect("casa", spanishFirst), ["Spanish", "English"])
  const anyFirst = [{ name: "Notes", characters: "any" }, { name: "Russian", characters: "cyrillic" }]
  assert.deepStrictEqual(detect("дом", anyFirst), ["Notes", "Russian"])
  assert.deepStrictEqual(detect("casa", anyFirst), ["Notes"])
})

test("custom alphabets", () => {
  const has = (word, chars) => M.matchesCharacters(word, chars)
  assert.ok(has("Été", "A-Za-zÀ-ÿ") && !has("дом", "A-Za-zÀ-ÿ"))
  assert.ok(has("гре", "а-яё") && has("ёж", "а-яё"))
  assert.ok(has("éA", "\\u00e9\\x41") && has("é", "\\u{e9}"))               // escapes spell a character
  assert.ok(has("x", "^x") && !has("y", "^x"))                              // ^ is not negation
  assert.ok(has("ab", "\\]ab\\\\\\-") && has("a", "a-"))                    // escaped ] \ - and a trailing -
  assert.ok(has("ab]", "ab"))                                               // punctuation in the word is skipped
  assert.ok(has("gre", "gre") && !has("greek", "gre"))                      // a set, not a preset name
  assert.ok(has("anything", "any"))
  // A broken set matches nothing instead of failing.
  for (const broken of ["z-a", "\\u12", "\\u{zz}", ""]) assert.ok(!has("a", broken), broken)
})

test("the language list from settings is cleaned up", () => {
  const names = (value) => list(M.normalizeLanguages(value)).map((l) => l.name + ":" + l.characters)
  const defaults = names(M.defaults())
  assert.deepStrictEqual(names(undefined), defaults)
  assert.deepStrictEqual(names([]), defaults)
  assert.deepStrictEqual(names("English"), defaults)
  assert.deepStrictEqual(names([{ name: "  ", characters: "latin" }, null, { name: " French " }]), ["French:any"])
  assert.deepStrictEqual(names([{ name: "Old", charset: "greek" }]), ["Old:greek"])  // older settings key
  assert.strictEqual(M.normalizeLanguages([{ name: "x".repeat(80) }])[0].name.length, 40)
  assert.strictEqual(M.normalizeLanguages(Array.from({ length: 30 }, (_, i) => ({ name: "L" + i }))).length, 20)
})

test("alphabet dropdown items", () => {
  assert.deepStrictEqual(list(M.scriptLabels()), ["Latin", "Cyrillic", "Greek", "Arabic", "Hebrew", "Any", "Custom…"])
  for (const label of list(M.scriptLabels()).slice(0, -1))
    assert.strictEqual(M.scriptLabel(M.scriptValue(label)), label)
  assert.strictEqual(M.scriptLabel("Latin"), "Latin")
  assert.strictEqual(M.scriptLabel("A-Za-zÀ-ÿ"), "Custom…")
  assert.strictEqual(M.scriptLabel(""), "Custom…")
  assert.strictEqual(M.scriptValue("Custom…"), "")
})

// ---- Already captured -------------------------------------------------------------

test("captured words are found in the file, prose is not", () => {
  const index = M.wordIndex([
    "# Vocabulary",
    "- **Casa** [Spanish] — la casa",
    "- **snake\\_case** [English]",
    "- **\\*\\*x\\*\\*** [English] — escaped stars",
    "  * **Привет**  [Russian]",
    "+ **plus**",
    "- **two  words**",
    "Some prose with **bold** text",
    "| **cell** | table |",
    "",
  ].join("\n"))
  for (const w of ["casa", "  CASA ", "snake_case", "**x**", "привет", "plus", "two words"])
    assert.ok(M.isCaptured(index, w), w)
  for (const w of ["bold", "cell", "vocabulary", "", "  "])
    assert.ok(!M.isCaptured(index, w), w)
})

test("duplicates ignore case, spacing and Unicode form, not letters", () => {
  const index = M.wordIndex("- **Cafe\u0301**\n- **ЁЖ**\n- **Straße**\n- **two   words**\n")
  assert.ok(M.isCaptured(index, "café"))                                     // decomposed in the file
  assert.ok(M.isCaptured(index, "ёж"))
  assert.ok(!M.isCaptured(index, "еж"))                                      // ё is not е
  assert.ok(M.isCaptured(index, "straße"))
  assert.ok(!M.isCaptured(index, "STRASSE"))                                 // ß is not ss
  assert.ok(M.isCaptured(index, " Two words "))
})

test("a written entry line is found again", () => {
  for (const w of ["snake_case", "a*b", "back\\slash", "a [b]", "x — y", "Ñandú", "cafe\u0301", "two words"])
    assert.ok(M.isCaptured(M.wordIndex(M.entryLine({ text: w, note: "n_o*te", tag: "X" })), w), w)
})

test("a word saved by append.sh is found again", () => {
  withScratch((home) => {
    const words = ["snake_case", "a*b", "back\\slash", "a [b]", "x — y", "cafe\u0301", "дом"]
    for (const w of words) append(home, "~/w.md", M.entryLine({ text: w, note: "note_1", tag: "Mixed" }).trim(), "Mixed")
    const index = M.wordIndex(fs.readFileSync(path.join(home, "w.md"), "utf8"))
    for (const w of words) assert.ok(M.isCaptured(index, w), w)
    assert.strictEqual(M.statsLine(M.addWord(index, "new", "Mixed"), "Mixed"), "8 words, 8 in Mixed")
  })
})

// ---- The toast's counts -----------------------------------------------------------

test("counts come from the [tag], else the ## section", () => {
  const file = "# Vocabulary\n- **simple** [English] — test\n- **loose**\n\n## Spanish\n\n- **casa** [Spanish]\n- **perro**\n### notes\n- **gato**\n- **Casa** [Spanish] — same word, counted once\n\n## C++ (old) [x]\n- **a**\n"
  assert.strictEqual(statsAfter(file, "nuevo", "Spanish"), "7 words, 4 in Spanish")
  assert.strictEqual(statsAfter(file, "new", "English"), "7 words, 2 in English")
  assert.strictEqual(statsAfter(file, "b", "C++ (old) [x]"), "7 words, 2 in C++ (old) [x]")
})

test("toast lines", () => {
  assert.strictEqual(statsAfter("", "casa", "Spanish"), "1 word, 1 in Spanish")
  assert.strictEqual(statsAfter("- **a**\n", "b", ""), "2 words")
  const file = "## Spanish\n\n- **casa** [Spanish]\n"
  assert.strictEqual(statsAfter(file, "perro", "Spanish"), "2 words, 2 in Spanish")
  assert.strictEqual(statsAfter(file, "Casa", "Spanish"), "Already had it. 1 word, 1 in Spanish")
  // The same word under another language is still a word you had.
  assert.strictEqual(statsAfter(file, "casa", "English"), "Already had it. 1 word, 0 in English")
})

test("Already had it is decided before the save, not after", () => {
  // The panel checks the word when Enter is pressed; if the index has seen the
  // new line by the time the save reports back, the word is still new.
  const file = "## Spanish\n\n- **casa** [Spanish]\n"
  const wasCaptured = M.isCaptured(M.wordIndex(file), "perro")
  const reread = M.wordIndex(file + "- **perro** [Spanish]\n")
  assert.strictEqual(M.statsLine(M.recordCapture(reread, M.normalizeWord("perro"), "Spanish", wasCaptured), "Spanish"), "2 words, 2 in Spanish")
})

// ---- Panel helpers ----------------------------------------------------------------

test("file name shown in the header", () => {
  assert.strictEqual(M.fileName("/home/a/Documents/word.md"), "word.md")
  assert.strictEqual(M.fileName("~/notes.md"), "notes.md")
  assert.strictEqual(M.fileName(""), "")
})

test("after the folder chooser, the file name is selected without its extension", () => {
  const selected = (p) => { const r = M.nameRange(p); return p.slice(r[0], r[1]) }
  assert.strictEqual(selected("~/Documents/words.md"), "words")
  assert.strictEqual(selected("/a.b/notes"), "notes")
  assert.strictEqual(selected("/x/.vocab"), ".vocab")
  assert.strictEqual(selected("/x/my.words.txt"), "my.words")
  assert.strictEqual(selected("/x/"), "")
})

test("clipboard prefill fills only an empty target field", () => {
  assert.strictEqual(M.prefillField("word", "", ""), "word")
  assert.strictEqual(M.prefillField("word", "casa", ""), "")
  assert.strictEqual(M.prefillField("word", " ", "kept note"), "word")
  assert.strictEqual(M.prefillField("context", "kept word", ""), "context")
  assert.strictEqual(M.prefillField("context", "", "note"), "")
  assert.strictEqual(M.prefillField("other", "", ""), "word")
})

test("clipboard text for the word field", () => {
  assert.strictEqual(M.clipboardText("  casa \n", "word"), "casa")
  assert.strictEqual(M.clipboardText("\n\n first  line \nsecond", "word"), "first line")
  assert.strictEqual(M.clipboardText("a\u0000b", "word"), "")                // binary
  assert.strictEqual(M.clipboardText("\ufffdPNG", "word"), "")
  assert.strictEqual(M.clipboardText("", "word"), "")
  assert.strictEqual(M.clipboardText("x".repeat(500), "word").length, 120)
})

test("clipboard text for the context field", () => {
  assert.strictEqual(M.clipboardText(" line one\r\nline two \n", "context"), "line one\nline two")
  assert.strictEqual(M.clipboardText("x".repeat(3000), "context").length, 2000)
  assert.strictEqual(M.clipboardText("a\u0000b", "context"), "")
})

test("the panel checks the same file append.sh writes", () => {
  withScratch((home) => {
    for (const input of ["~/a/w.md", "b/w.md", "w.md", home + "/c/w.md", "  ~/d.md  "])
      assert.strictEqual(M.resolvePath(input, home), append(home, "--touch", input.trim()), input)
    assert.strictEqual(M.resolvePath("  ", home), "")
  })
})

console.log("RESULT model " + passed + " " + failed + " 0")
process.exitCode = failed ? 1 : 0
