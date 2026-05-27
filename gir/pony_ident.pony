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
  fun safe_param(gir_name: String): String val =>
    """
    Convert a GIR parameter/binding name into a Pony-legal
    identifier:

      - Hyphens become underscores       (e.g. "close-request" -> "close_request")
      - Trailing underscores are stripped (Pony disallows them on bindings)
      - Reserved words get a prime suffix ("match" -> "match'",
        "ref" -> "ref'", "error" -> "error'")
      - Empty input becomes "arg" so calling sites always have a name

    The transformation is total. It is not invertible — `safe_param("match")`
    and `safe_param("match'")` both yield `"match'"` — but invertibility
    is not currently needed by any consumer.

    The prime suffix is legal only for variable bindings and
    parameter names; do not use this for method names. Use
    `safe_method` for that — Pony's grammar accepts primes in let/var
    bindings but rejects them in method declarations.
    """
    if gir_name.size() == 0 then return "arg" end
    let n = _normalize_and_trim(gir_name)
    if n.size() == 0 then return "arg" end
    if is_reserved(n) then n + "'" else n end

  fun safe_method(gir_name: String): String val =>
    """
    Convert a GIR method name into a Pony-legal method identifier:

      - Hyphens become underscores
      - Trailing underscores are stripped
      - Reserved words get a `g` prefix ("match" -> "gmatch",
        "ref" -> "gref", "error" -> "gerror")
      - Empty input becomes "method"

    The `g` prefix is chosen over the `'` suffix used by
    `safe_param` because Pony method names disallow primes (and
    trailing/double underscores). `g` echoes the GObject naming
    convention and stays a legal method identifier.

    Pathological case: if the GIR namespace happens to define both
    `match` and `gmatch` methods on the same type, both will map to
    `gmatch` and the second emission will collide. We haven't seen
    this in practice on Gtk-4.0 / Gio-2.0 / GLib-2.0 / GObject-2.0;
    revisit if it surfaces.
    """
    if gir_name.size() == 0 then return "method" end
    let n = _normalize_and_trim(gir_name)
    if n.size() == 0 then return "method" end
    if is_reserved(n) then "g" + n else n end

  fun _normalize_and_trim(gir_name: String): String val =>
    """
    Shared first half of both munges: replace hyphens, drop trailing
    underscores. The collision-resolution suffix/prefix is applied
    by the caller.
    """
    let normalized = recover iso String end
    for c in gir_name.values() do
      if c == '-' then normalized.push('_') else normalized.push(c) end
    end
    var n: String val = consume normalized
    while (n.size() > 0) and
      try (n(n.size() - 1)? == '_') else false end
    do
      n = n.substring(0, (n.size() - 1).isize())
    end
    n

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
