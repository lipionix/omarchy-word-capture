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

test("flattens newlines", () => {
  assert.strictEqual(M.entryLine({ text: "a\nb", note: "c\r\n d", tag: "" }), "- **a b** — c d\n")
})

test("escape round-trips", () => {
  for (const s of ["snake_case", "**x**", "a\\b", "plain", "a\\*b"])
    assert.strictEqual(M.unescapeMarkdown(M.escapeMarkdown(s)), s)
})

test("detects by script", () => {
  assert.deepStrictEqual(Array.from(M.detect("привет", M.defaults())), ["Russian"])
  assert.deepStrictEqual(Array.from(M.detect("hola", M.defaults())), ["English", "Spanish"])
})

console.log(passed + " passed")
