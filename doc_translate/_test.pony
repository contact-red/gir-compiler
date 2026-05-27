// Tests for the doc_translate package.
//
// Generative tests (PonyCheck) cover universal properties of the
// translator: pure text passes through, generated outputs are
// well-formed markdown, recognized refs either resolve or
// diagnose. Example-based tests pin down specific gtk-doc / gi-docgen
// markup forms; these mirror real samples from the GIR corpus probe
// so behaviour on actual inputs stays nailed down.

use "pony_check"
use "pony_test"
use "collections"
use "../gir"


actor Main is TestList
  new create(env: Env) =>
    PonyTest(env, this)

  new make() => None

  fun tag tests(test: PonyTest) =>
    // Example-based
    test(_TestEmptyInput)
    test(_TestPlainText)
    test(_TestTrueFalseNullSpecialCases)
    test(_TestParamReference)
    test(_TestUnresolvedTypeRefFallback)
    test(_TestResolvedTypeRefLink)
    test(_TestResolvedModernClassRef)
    test(_TestResolvedModernMethodRef)
    test(_TestResolvedModernMethodRefMungesReservedWord)
    test(_TestFencedCodeBlockPassesThrough)
    test(_TestRefsInsideFencedBlockNotTranslated)
    test(_TestInlineCodePassesThrough)
    test(_TestLegacyCodeBlockWithLanguage)
    test(_TestLegacyCodeBlockNoLanguage)
    test(_TestHeadingDemotion)
    test(_TestHeadingDemotionCapsAtH6)
    test(_TestHashMidLineNotTreatedAsHeading)
    test(_TestEntityDecode)
    test(_TestPercentNotConstantPassesThrough)
    test(_TestMarkdownLinkPassesThrough)
    test(_TestModernRefMalformedNotTranslated)
    // Property-based
    test(Property1UnitTest[String val](_PropPlainTextIsIdentity))
    test(Property1UnitTest[String val](_PropEveryHashRefGetsLinkOrDiag))


// ---------------------------------------------------------------
// Test fixtures
// ---------------------------------------------------------------

primitive _Fixtures
  fun empty_model_ctx(): TranslateContext val ? =>
    """
    A context whose model contains one empty namespace (Gtk). Used
    for tests that don't need to resolve anything.
    """
    TranslateContext("Gtk", _make_minimal_model()?)

  fun gtk_model_ctx(): TranslateContext val ? =>
    """
    A context whose model has Gtk.Widget defined (with a `show`
    method on it), so type and method refs to it resolve.
    """
    TranslateContext("Gtk", _make_model_with_widget()?)

  fun gtk_model_ctx_with_filter(): TranslateContext val ? =>
    """
    A context whose model has Gtk.Filter defined with a `match`
    method — used to test that doc-URL anchors get the same
    reserved-word munge the emitter applies (`match` -> `match'`).
    """
    TranslateContext("Gtk", _make_model_with_filter()?)

  fun _make_minimal_model(): GirModel val ? =>
    let ns = _empty_namespace("Gtk")
    let repos = _wrap_namespace(ns)
    match GirValidator(repos)
    | let m: GirModel val => m
    else error
    end

  fun _make_model_with_widget(): GirModel val ? =>
    let show_method = RawGirMethod(
      RawGirMethodKindMethod, "show", "gtk_widget_show",
      false, "",
      RawGirReturnValue(RawGirType("none", "void"), "none", false, ""),
      recover val Array[RawGirParameter val] end)
    let methods = recover val
      let arr = Array[RawGirMethod val](1)
      arr.push(show_method)
      arr
    end
    let widget = RawGirClass(
      "Widget", "GtkWidget", "", "",
      recover val Array[String val] end,
      recover val Array[RawGirMethod val] end,
      methods,
      recover val Array[RawGirProperty val] end,
      recover val Array[RawGirSignal val] end)
    let classes = recover val
      let arr = Array[RawGirClass val](1)
      arr.push(widget)
      arr
    end
    let ns = RawGirNamespace(
      "Gtk", "4.0", "Gtk", "",
      classes,
      recover val Array[RawGirInterface val] end,
      recover val Array[RawGirRecord val] end,
      recover val Array[RawGirEnumeration val] end,
      recover val Array[RawGirBitfield val] end,
      recover val Array[RawGirCallback val] end,
      recover val Array[RawGirAlias val] end,
      recover val Array[RawGirMethod val] end)
    let repos = _wrap_namespace(ns)
    match GirValidator(repos)
    | let m: GirModel val => m
    else error
    end

  fun _make_model_with_filter(): GirModel val ? =>
    let match_method = RawGirMethod(
      RawGirMethodKindMethod, "match", "gtk_filter_match",
      false, "",
      RawGirReturnValue(RawGirType("gboolean", "gboolean"), "none", false, ""),
      recover val Array[RawGirParameter val] end)
    let methods = recover val
      let arr = Array[RawGirMethod val](1)
      arr.push(match_method)
      arr
    end
    let filter = RawGirClass(
      "Filter", "GtkFilter", "", "",
      recover val Array[String val] end,
      recover val Array[RawGirMethod val] end,
      methods,
      recover val Array[RawGirProperty val] end,
      recover val Array[RawGirSignal val] end)
    let classes = recover val
      let arr = Array[RawGirClass val](1)
      arr.push(filter)
      arr
    end
    let ns = RawGirNamespace(
      "Gtk", "4.0", "Gtk", "",
      classes,
      recover val Array[RawGirInterface val] end,
      recover val Array[RawGirRecord val] end,
      recover val Array[RawGirEnumeration val] end,
      recover val Array[RawGirBitfield val] end,
      recover val Array[RawGirCallback val] end,
      recover val Array[RawGirAlias val] end,
      recover val Array[RawGirMethod val] end)
    let repos = _wrap_namespace(ns)
    match GirValidator(repos)
    | let m: GirModel val => m
    else error
    end

  fun _empty_namespace(name: String val): RawGirNamespace val =>
    RawGirNamespace(
      name, "4.0", name, "",
      recover val Array[RawGirClass val] end,
      recover val Array[RawGirInterface val] end,
      recover val Array[RawGirRecord val] end,
      recover val Array[RawGirEnumeration val] end,
      recover val Array[RawGirBitfield val] end,
      recover val Array[RawGirCallback val] end,
      recover val Array[RawGirAlias val] end,
      recover val Array[RawGirMethod val] end)

  fun _wrap_namespace(ns: RawGirNamespace val)
    : Array[RawGirRepository val] val
  =>
    recover val
      let arr = Array[RawGirRepository val](1)
      arr.push(RawGirRepository(recover val
        let nss = Array[RawGirNamespace val](1)
        nss.push(ns)
        nss
      end))
      arr
    end


// ---------------------------------------------------------------
// Example-based tests
// ---------------------------------------------------------------

class iso _TestEmptyInput is UnitTest
  fun name(): String => "doc_translate/empty input"
  fun apply(h: TestHelper) ? =>
    let r = DocTranslate("", _Fixtures.empty_model_ctx()?)
    h.assert_eq[String]("", r.body)
    h.assert_eq[USize](0, r.diagnostics.size())


class iso _TestPlainText is UnitTest
  fun name(): String => "doc_translate/plain text passes through"
  fun apply(h: TestHelper) ? =>
    let r = DocTranslate(
      "Plain text with no markup at all.", _Fixtures.empty_model_ctx()?)
    h.assert_eq[String]("Plain text with no markup at all.", r.body)
    h.assert_eq[USize](0, r.diagnostics.size())


class iso _TestTrueFalseNullSpecialCases is UnitTest
  fun name(): String => "doc_translate/%TRUE %FALSE %NULL"
  fun apply(h: TestHelper) ? =>
    let r = DocTranslate(
      "returns %TRUE on success, %FALSE on failure, %NULL otherwise",
      _Fixtures.empty_model_ctx()?)
    h.assert_eq[String](
      "returns `true` on success, `false` on failure, `None` otherwise",
      r.body)
    h.assert_eq[USize](0, r.diagnostics.size())


class iso _TestParamReference is UnitTest
  fun name(): String => "doc_translate/@param -> `param`"
  fun apply(h: TestHelper) ? =>
    let r = DocTranslate("frees @data; @data must not be null",
      _Fixtures.empty_model_ctx()?)
    h.assert_eq[String]("frees `data`; `data` must not be null", r.body)


class iso _TestUnresolvedTypeRefFallback is UnitTest
  fun name(): String => "doc_translate/unresolved #CType -> inline code + diag"
  fun apply(h: TestHelper) ? =>
    let r = DocTranslate("see #GtkNothing for details",
      _Fixtures.empty_model_ctx()?)
    h.assert_eq[String]("see `GtkNothing` for details", r.body)
    h.assert_eq[USize](1, r.diagnostics.size())
    match r.diagnostics(0)?
    | let d: UnresolvedTypeRef val =>
      h.assert_eq[String]("GtkNothing", d.ref_text)
    else
      h.fail("expected UnresolvedTypeRef, got something else")
    end


class iso _TestResolvedTypeRefLink is UnitTest
  fun name(): String => "doc_translate/resolved #CType -> link"
  fun apply(h: TestHelper) ? =>
    let r = DocTranslate("see #GtkWidget for the base class",
      _Fixtures.gtk_model_ctx()?)
    h.assert_eq[String](
      "see [Gtk.Widget](gtk-Widget.md) for the base class", r.body)
    h.assert_eq[USize](0, r.diagnostics.size())


class iso _TestResolvedModernClassRef is UnitTest
  fun name(): String => "doc_translate/[class@Gtk.Widget] -> link"
  fun apply(h: TestHelper) ? =>
    let r = DocTranslate("uses [class@Gtk.Widget] as the receiver",
      _Fixtures.gtk_model_ctx()?)
    h.assert_eq[String](
      "uses [Gtk.Widget](gtk-Widget.md) as the receiver", r.body)


class iso _TestResolvedModernMethodRef is UnitTest
  fun name(): String => "doc_translate/[method@Gtk.Widget.show] -> link"
  fun apply(h: TestHelper) ? =>
    let r = DocTranslate("call [method@Gtk.Widget.show] to display",
      _Fixtures.gtk_model_ctx()?)
    h.assert_eq[String](
      "call [Gtk.Widget.show](gtk-Widget.md#show) to display", r.body)


class iso _TestResolvedModernMethodRefMungesReservedWord is UnitTest
  fun name(): String =>
    "doc_translate/[method@Gtk.Filter.match] anchor uses match'"

  fun apply(h: TestHelper) ? =>
    let r = DocTranslate("call [method@Gtk.Filter.match]",
      _Fixtures.gtk_model_ctx_with_filter()?)
    // The visible label AND the URL anchor should carry the munged
    // name so the link target matches what the emitter writes as
    // the Pony method name.
    h.assert_eq[String](
      "call [Gtk.Filter.match'](gtk-Filter.md#match')", r.body)


class iso _TestFencedCodeBlockPassesThrough is UnitTest
  fun name(): String => "doc_translate/fenced code passes verbatim"
  fun apply(h: TestHelper) ? =>
    let input = "before\n```c\nint x = 0;\n```\nafter"
    let r = DocTranslate(input, _Fixtures.empty_model_ctx()?)
    h.assert_eq[String](input, r.body)


class iso _TestRefsInsideFencedBlockNotTranslated is UnitTest
  fun name(): String => "doc_translate/refs inside ``` block unchanged"
  fun apply(h: TestHelper) ? =>
    let input = "```\n#GtkWidget x = %TRUE\n```"
    let r = DocTranslate(input, _Fixtures.gtk_model_ctx()?)
    h.assert_eq[String](input, r.body)
    h.assert_eq[USize](0, r.diagnostics.size())


class iso _TestInlineCodePassesThrough is UnitTest
  fun name(): String => "doc_translate/`code` span unchanged"
  fun apply(h: TestHelper) ? =>
    let r = DocTranslate("the `#GtkWidget` reference",
      _Fixtures.gtk_model_ctx()?)
    h.assert_eq[String]("the `#GtkWidget` reference", r.body)
    h.assert_eq[USize](0, r.diagnostics.size())


class iso _TestLegacyCodeBlockWithLanguage is UnitTest
  fun name(): String => "doc_translate/|[ <!--language=C--> ... ]| -> ```C"
  fun apply(h: TestHelper) ? =>
    let input = "|[<!-- language=\"C\" -->\nint x = 0;\n]|"
    let r = DocTranslate(input, _Fixtures.empty_model_ctx()?)
    h.assert_eq[String]("```C\nint x = 0;\n```", r.body)


class iso _TestLegacyCodeBlockNoLanguage is UnitTest
  fun name(): String => "doc_translate/|[ ... ]| no language -> ```"
  fun apply(h: TestHelper) ? =>
    let input = "|[\nint x = 0;\n]|"
    let r = DocTranslate(input, _Fixtures.empty_model_ctx()?)
    h.assert_eq[String]("```\nint x = 0;\n```", r.body)


class iso _TestHeadingDemotion is UnitTest
  fun name(): String => "doc_translate/headings demoted by one"
  fun apply(h: TestHelper) ? =>
    let r = DocTranslate("# H1\n## H2\n### H3\n",
      _Fixtures.empty_model_ctx()?)
    h.assert_eq[String]("## H1\n### H2\n#### H3\n", r.body)


class iso _TestHeadingDemotionCapsAtH6 is UnitTest
  fun name(): String => "doc_translate/heading demotion caps at H6"
  fun apply(h: TestHelper) ? =>
    let r = DocTranslate("###### H6\n", _Fixtures.empty_model_ctx()?)
    h.assert_eq[String]("###### H6\n", r.body)


class iso _TestHashMidLineNotTreatedAsHeading is UnitTest
  fun name(): String => "doc_translate/mid-line # not demoted"
  fun apply(h: TestHelper) ? =>
    let r = DocTranslate("see issue #42 for details",
      _Fixtures.empty_model_ctx()?)
    h.assert_eq[String]("see issue #42 for details", r.body)


class iso _TestEntityDecode is UnitTest
  fun name(): String => "doc_translate/decodes lingering &amp; &lt; &gt;"
  fun apply(h: TestHelper) ? =>
    // In practice libxml2 decodes these for us, but the translator
    // should be safe against them anyway.
    let r = DocTranslate("a &amp; b &lt; c &gt; d",
      _Fixtures.empty_model_ctx()?)
    h.assert_eq[String]("a & b < c > d", r.body)


class iso _TestPercentNotConstantPassesThrough is UnitTest
  fun name(): String => "doc_translate/% not followed by constant ident"
  fun apply(h: TestHelper) ? =>
    let r = DocTranslate("50% complete", _Fixtures.empty_model_ctx()?)
    h.assert_eq[String]("50% complete", r.body)


class iso _TestMarkdownLinkPassesThrough is UnitTest
  fun name(): String => "doc_translate/[text](url) markdown link unchanged"
  fun apply(h: TestHelper) ? =>
    let r = DocTranslate("see [the docs](https://example.com)",
      _Fixtures.empty_model_ctx()?)
    h.assert_eq[String]("see [the docs](https://example.com)", r.body)


class iso _TestModernRefMalformedNotTranslated is UnitTest
  fun name(): String => "doc_translate/[class@] malformed unchanged"
  fun apply(h: TestHelper) ? =>
    let r = DocTranslate("[class@] is malformed",
      _Fixtures.empty_model_ctx()?)
    h.assert_eq[String]("[class@] is malformed", r.body)


// ---------------------------------------------------------------
// Property-based tests
// ---------------------------------------------------------------

class iso _PropPlainTextIsIdentity is Property1[String val]
  fun name(): String => "doc_translate/property: plain text identity"

  fun gen(): Generator[String val] =>
    // ASCII letters only — no markup-triggering characters.
    Generators.ascii(0, 60, ASCIILetters)

  fun property(arg1: String val, ph: PropertyHelper) ? =>
    let r = DocTranslate(arg1, _Fixtures.empty_model_ctx()?)
    ph.assert_eq[String](arg1, r.body)
    ph.assert_eq[USize](0, r.diagnostics.size())


class iso _PropEveryHashRefGetsLinkOrDiag is Property1[String val]
  fun name(): String => "doc_translate/property: every #Ref links or diagnoses"

  fun gen(): Generator[String val] =>
    // Inputs of the form "see #<uppercase><letters> for details" against
    // an empty model. With no types known, the ref must always produce
    // a diagnostic AND fall back to inline-code rendering.
    Generators.u8(85, 90).map[String val]({(c) =>
      recover val
        let s = String(24)
        s.append("see #")
        s.push(c)
        s.append("ype for details")
        s
      end
    })

  fun property(arg1: String val, ph: PropertyHelper) ? =>
    let r = DocTranslate(arg1, _Fixtures.empty_model_ctx()?)
    ph.assert_eq[USize](1, r.diagnostics.size())
    ph.assert_true(r.body.contains("`"),
      "expected inline-code fallback in body, got: " + r.body)
    ph.assert_false(r.body.contains("#"),
      "expected #-prefix consumed, got: " + r.body)
