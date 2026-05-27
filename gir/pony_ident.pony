// PonyIdent — the canonical GIR-name → Pony-identifier munge.
//
// Lives in the `gir` package (not `emitter`) so it can be called
// from anywhere a GIR name crosses into Pony source: the emitter
// (when writing parameter and method names) and the doc translator
// (when computing the URL anchor pony-doc would generate for those
// same names). Having one function avoid drift — a name that gets
// suffixed with `'` in the emitted code must get the same `'` in
// the docs URL or the link breaks.

primitive PonyIdent
  fun safe(gir_name: String): String val =>
    """
    Convert a GIR identifier (parameter name, method name, signal
    handler name) into a Pony-legal identifier:

      - Hyphens become underscores       (e.g. "close-request" -> "close_request")
      - Trailing underscores are stripped (Pony disallows them on bindings)
      - Reserved words get a prime suffix ("match" -> "match'",
        "ref" -> "ref'", "error" -> "error'")
      - Empty input becomes "arg" so calling sites always have a name

    The transformation is total: every input string produces some
    legal Pony identifier. It is not invertible — `safe("match")`
    and `safe("match'")` both yield `"match'"` — but invertibility
    is not currently needed by any consumer.
    """
    if gir_name.size() == 0 then return "arg" end
    let normalized = recover iso String end
    for c in gir_name.values() do
      if c == '-' then normalized.push('_') else normalized.push(c) end
    end
    var n: String val = consume normalized
    // Strip trailing underscores — Pony disallows them.
    while (n.size() > 0) and
      try (n(n.size() - 1)? == '_') else false end
    do
      n = n.substring(0, (n.size() - 1).isize())
    end
    if n.size() == 0 then return "arg" end
    if is_reserved(n) then n + "'" else n end

  fun is_reserved(s: String): Bool =>
    """
    The Pony reserved words we've seen GIR identifiers collide
    with, plus the obvious-keyword set. Not exhaustive — add as
    new collisions surface from real GIR data.
    """
    match s
    | "actor" | "class" | "primitive" | "interface" | "trait"
    | "type" | "struct" | "object" | "lambda" | "this"
    | "is" | "isnt" | "or" | "and" | "xor" | "not"
    | "if" | "then" | "else" | "elseif" | "end"
    | "while" | "do" | "for" | "in" | "repeat" | "until"
    | "match" | "as" | "var" | "let" | "embed" | "consume"
    | "error" | "recover" | "compile_error"
    | "try" | "with" | "where"
    | "iso" | "trn" | "ref" | "val" | "box" | "tag"
    | "true" | "false" | "use" | "new" | "fun" | "be"
    | "return" | "break" | "continue"
    | "addressof" | "digestof"
    => true
    else false
    end
