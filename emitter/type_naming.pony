// TypeNaming — shared helpers for mapping GIR names to Pony names.
//
// The convention:
//
//   GIR qname "Gtk.Application"   -> Pony type "GtkApplication"
//   GIR qname "Gio.Application"   -> Pony type "GioApplication"
//   GIR qname "GObject.Object"    -> Pony type "GObjectObject"
//
// And for GIR primitives (the "built-in" names like gint, guint,
// utf8, gboolean...), we map directly to Pony built-in types so
// generated code doesn't have to wrap or convert.

primitive TypeNaming
  fun pony_type_name(qname: String): String val =>
    """
    "Gtk.Application" -> "GtkApplication". Strips the dot.
    Returns the qname unchanged if it has no dot (shouldn't happen
    for validator-built qnames).
    """
    try
      let idx = qname.find(".")?
      let ns: String val = qname.substring(0, idx)
      let local: String val = qname.substring(idx + 1)
      ns + local
    else
      qname.string()
    end

  fun pony_type_from_namespaced_ref(
    gir_name: String,
    current_ns: String)
    : String val
  =>
    """
    Resolve a method/parameter/return type's GIR `name` attribute
    to its Pony type name. Handles four cases:

      - Empty -> "None" (defensive sentinel)
      - GIR primitive ("gint", "utf8", ...) -> Pony primitive
      - Qualified ("Gio.Application") -> "GioApplication"
      - Bare ("Window") -> "<current_ns><name>" (e.g. "GtkWindow")
    """
    if gir_name.size() == 0 then return "None" end

    match _primitive_mapping(gir_name)
    | let p: String val => return p
    end

    try
      let idx = gir_name.find(".")?
      let ns: String val = gir_name.substring(0, idx)
      let local: String val = gir_name.substring(idx + 1)
      ns + local
    else
      current_ns + gir_name
    end

  fun gir_primitive_pony(gir_name: String): (String val | None) =>
    """
    Public: GIR built-in -> Pony built-in, or None if not a GIR
    primitive. Useful for code-gen sites that need to distinguish
    primitives (which always exist) from object types (which may or
    may not be in the loaded plan).
    """
    _primitive_mapping(gir_name)

  fun safe_param_name(gir_name: String): String val =>
    """
    GIR parameter names sometimes collide with Pony reserved words
    (`error`, `object`, `type`, `match`, ...), use kebab-case, or
    have trailing underscores (Pony forbids those). Returns a
    Pony-legal identifier:
      - Hyphens become underscores
      - Trailing underscores are stripped
      - Reserved words get a prime suffix ("error" -> "error'")
      - Empty input becomes "arg"
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
    if _is_reserved(n) then n + "'" else n end


  fun _is_reserved(s: String): Bool =>
    """
    Pony reserved words that conflict with our param-name emission.
    Not exhaustive — just the ones we've hit. Add more as new
    collisions surface from real GIR data.
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


  fun _primitive_mapping(gir_name: String): (String val | None) =>
    """
    GIR's documented C-typedef -> Pony built-in. Anything not in
    this table falls through to the namespaced-name path.
    """
    match gir_name
    | "none" => "None"
    | "gboolean" => "Bool"
    | "gint" => "I32"
    | "gint8" => "I8"
    | "gint16" => "I16"
    | "gint32" => "I32"
    | "gint64" => "I64"
    | "guint" => "U32"
    | "guint8" => "U8"
    | "guint16" => "U16"
    | "guint32" => "U32"
    | "guint64" => "U64"
    | "gfloat" => "F32"
    | "gdouble" => "F64"
    | "gchar" => "I8"
    | "guchar" => "U8"
    | "gsize" => "USize"
    | "gssize" => "ISize"
    | "glong" => "I64"        // 64-bit Linux; would be I32 on Win32
    | "gulong" => "U64"       // 64-bit Linux; would be U32 on Win32
    | "gshort" => "I16"
    | "gushort" => "U16"
    | "gunichar" => "U32"
    | "utf8" => "String"
    | "filename" => "String"
    | "gpointer" => "Pointer[None] tag"
    | "gconstpointer" => "Pointer[None] tag"
    | "GType" => "USize"
    else None
    end
