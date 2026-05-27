// DocstringWriter — turn a raw GIR <doc> string into a Pony
// triple-quoted docstring with the right indent.
//
// The emitter calls into this whenever it wants to attach a
// docstring to a generated type or method body. Behaviour:
//
//   - If `raw_doc` is empty, emits nothing (empty string returned).
//   - Otherwise runs the text through `DocTranslate` and writes:
//
//         {indent}"""
//         {indent}{translated body, one line per line}
//         {indent}"""
//
//     followed by a trailing newline so the next emitted line in the
//     surrounding type/method body starts cleanly.
//
// We assume `"""` doesn't appear in the translated text (empirically
// verified against the four target GIR namespaces — zero hits). If
// that assumption ever breaks, the generated Pony will fail to parse,
// surfacing the problem immediately rather than silently miscompiling.

use "../doc_translate"
use "../gir"


primitive DocstringWriter
  fun apply(
    raw_doc: String val,
    ctx: (TranslateContext val | None),
    indent: String val)
    : String val
  =>
    """
    Format `raw_doc` as a Pony docstring with `indent` prepended to
    every line. Returns an empty string when docstrings are
    suppressed (`ctx` is None) or when the raw doc has no text.
    """
    let translate_ctx = match ctx
                        | let c: TranslateContext val => c
                        | None => return ""
                        end
    if raw_doc.size() == 0 then return "" end
    let translated = DocTranslate(raw_doc, translate_ctx)
    let body = translated.body
    if body.size() == 0 then return "" end

    let buf = recover iso String(body.size() + 32) end
    buf.append(indent)
    buf.append("\"\"\"\n")
    // Walk body line by line. Each non-empty line gets `indent`
    // prepended; blank lines stay blank.
    var line_start: USize = 0
    var i: USize = 0
    while i < body.size() do
      try
        if body(i)? == '\n' then
          if i > line_start then
            buf.append(indent)
            buf.append(body.substring(line_start.isize(), i.isize()))
          end
          buf.push('\n')
          line_start = i + 1
        end
      end
      i = i + 1
    end
    // Tail (no trailing newline in body)
    if line_start < body.size() then
      buf.append(indent)
      buf.append(body.substring(line_start.isize()))
      buf.push('\n')
    end
    buf.append(indent)
    buf.append("\"\"\"\n")
    consume buf
