// Public types of the `doc_translate` package.
//
// The translator's contract is:
//   raw GIR <doc> text  +  TranslateContext  ->  TranslatedDoc val
// where the body of the TranslatedDoc is Pony-docstring-ready
// markdown (compatible with `pony-doc`'s pass-through to MkDocs),
// and the diagnostics carry per-reference failures.

use "../gir"


class val TranslateContext
  """
  Inputs the translator needs that aren't part of the raw doc text:
  which namespace the doc lives in (so unqualified refs can resolve
  against the local namespace), and the model to look references up
  against.
  """
  let from_namespace: NamespaceName
  let model: GirModel val

  new val create(
    from_namespace': NamespaceName,
    model': GirModel val)
  =>
    from_namespace = from_namespace'
    model = model'


class val TranslatedDoc
  """
  The translator's output. `body` is markdown text suitable for use
  verbatim as a Pony docstring; `diagnostics` lists every reference
  the translator recognized as such but could not resolve. An empty
  diagnostics array does not mean the body is perfect — the
  translator falls back to inline code for unresolvable refs, so the
  body is always usable even when diagnostics is non-empty.
  """
  let body: String val
  let diagnostics: Array[TranslateDiag val] val

  new val create(
    body': String val,
    diagnostics': Array[TranslateDiag val] val)
  =>
    body = body'
    diagnostics = diagnostics'
