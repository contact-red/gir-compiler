// Diagnostic vocabulary for `doc_translate`.
//
// Each variant carries the source ref text so callers (typically the
// gir-docs binary at the end of a run) can aggregate diagnostics and
// print useful warnings without going back to the original source.


class val UnresolvedTypeRef
  """
  A reference looked like a type but did not resolve. Carries the
  exact source text after the marker (e.g. "GtkSomethingMissing" for
  `#GtkSomethingMissing`, "Gtk.Removed" for `[class@Gtk.Removed]`).
  """
  let ref_text: String val

  new val create(ref_text': String val) =>
    ref_text = ref_text'

  fun box describe(): String iso^ =>
    ("unresolved type ref: " + ref_text).clone()


class val UnresolvedMethodRef
  """
  A reference looked like a method/function/constructor/vfunc/signal
  but did not resolve against the model. Carries the full source ref
  text (e.g. "Gtk.Widget.removed_method").
  """
  let ref_text: String val

  new val create(ref_text': String val) =>
    ref_text = ref_text'

  fun box describe(): String iso^ =>
    ("unresolved method ref: " + ref_text).clone()


class val UnresolvedConstantRef
  """
  A `%CONSTANT_NAME` or `[const@…]` reference that did not resolve
  against the model. The translator falls back to wrapping the
  source text in inline code.
  """
  let ref_text: String val

  new val create(ref_text': String val) =>
    ref_text = ref_text'

  fun box describe(): String iso^ =>
    ("unresolved constant ref: " + ref_text).clone()


class val InvalidMarkup
  """
  Some structural markup (a fence, a legacy `|[…]|` block) was
  opened but not properly closed in the input. The translator
  recovers by treating the open as literal text; this diagnostic
  records where the trouble was so source authors can fix the GIR.
  """
  let detail: String val
  let position: USize

  new val create(detail': String val, position': USize) =>
    detail = detail'
    position = position'

  fun box describe(): String iso^ =>
    ("invalid markup at byte " + position.string() + ": " + detail).clone()


type TranslateDiag is
  ( UnresolvedTypeRef val
  | UnresolvedMethodRef val
  | UnresolvedConstantRef val
  | InvalidMarkup val )
