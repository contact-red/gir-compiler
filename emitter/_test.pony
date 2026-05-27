// Tests for emitter helpers that are easy to exercise in isolation.
// The bulk of emitter behaviour is verified end-to-end by building
// the gtk4 hello example (and, soon, by running gir-docs against the
// real GIR corpus). These tests cover small functions that are easy
// to break and tricky to spot in a generated source file.

use "pony_test"
use "../doc_translate"
use "../gir"


actor Main is TestList
  new create(env: Env) =>
    PonyTest(env, this)

  new make() => None

  fun tag tests(test: PonyTest) =>
    test(_TestDocstringWriterNoCtx)
    test(_TestDocstringWriterEmptyDoc)
    test(_TestDocstringWriterSingleLine)
    test(_TestDocstringWriterMultiLine)


class iso _TestDocstringWriterNoCtx is UnitTest
  fun name(): String => "DocstringWriter/no ctx -> empty"
  fun apply(h: TestHelper) =>
    h.assert_eq[String]("", DocstringWriter("anything", None, "  "))


class iso _TestDocstringWriterEmptyDoc is UnitTest
  fun name(): String => "DocstringWriter/empty doc -> empty"
  fun apply(h: TestHelper) ? =>
    let ctx = TranslateContext("Gtk", _TestModel.empty()?)
    h.assert_eq[String]("", DocstringWriter("", ctx, "  "))


class iso _TestDocstringWriterSingleLine is UnitTest
  fun name(): String => "DocstringWriter/single line"
  fun apply(h: TestHelper) ? =>
    let ctx = TranslateContext("Gtk", _TestModel.empty()?)
    let out = DocstringWriter("Shows the widget.", ctx, "  ")
    h.assert_eq[String]("  \"\"\"\n  Shows the widget.\n  \"\"\"\n", out)


class iso _TestDocstringWriterMultiLine is UnitTest
  fun name(): String => "DocstringWriter/multi line preserves blank lines"
  fun apply(h: TestHelper) ? =>
    let ctx = TranslateContext("Gtk", _TestModel.empty()?)
    let out = DocstringWriter("line one\n\nline two\n", ctx, "    ")
    h.assert_eq[String](
      "    \"\"\"\n    line one\n\n    line two\n    \"\"\"\n",
      out)


primitive _TestModel
  fun empty(): GirModel val ? =>
    let ns = RawGirNamespace(
      "Gtk", "4.0", "Gtk", "",
      recover val Array[RawGirClass val] end,
      recover val Array[RawGirInterface val] end,
      recover val Array[RawGirRecord val] end,
      recover val Array[RawGirEnumeration val] end,
      recover val Array[RawGirBitfield val] end,
      recover val Array[RawGirCallback val] end,
      recover val Array[RawGirAlias val] end,
      recover val Array[RawGirMethod val] end)
    let repo = RawGirRepository(recover val
      let nss = Array[RawGirNamespace val](1)
      nss.push(ns)
      nss
    end)
    let repos = recover val
      let arr = Array[RawGirRepository val](1)
      arr.push(repo)
      arr
    end
    match GirValidator(repos)
    | let m: GirModel val => m
    else error
    end
