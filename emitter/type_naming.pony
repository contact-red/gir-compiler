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
//
// Identifier-level munging (parameter and method names, reserved-
// word avoidance) lives in `gir/PonyIdent` so both the emitter and
// the doc translator route through one implementation.

use "../gir"

primitive TypeNaming
  fun pony_type_name(c_type: String, qname: String): String val =>
    """
    The Pony spelling for a GIR type. Uses the GIR-declared `c:type`
    directly when present — so e.g. `Gio.Application` (c:type=GApplication)
    renders as `GApplication`, not `GioApplication`. This keeps the
    generated names in lockstep with the actual C API and with what
    pony-doc shows on the documentation page.

    Falls back to the namespace-prepended form when the GIR didn't
    declare a c:type (rare, defensive).
    """
    if c_type.size() > 0 then return c_type end
    try
      let idx = qname.find(".")?
      let ns: String val = qname.substring(0, idx)
      let local: String val = qname.substring(idx + 1)
      ns + local
    else
      qname.string()
    end

  fun pony_name_for_node(node: GirNodeRef, fallback_qname: String): String val =>
    """
    Read the c:type off a resolved GIR node and route it through
    `pony_type_name`. Centralizes the per-kind c_type extraction so
    callers don't repeat the match arms.
    """
    let c_type = match node
                 | let c: GirNodeClass => c.target.c_type
                 | let i: GirNodeInterface => i.target.c_type
                 | let r: GirNodeRecord => r.target.c_type
                 | let e: GirNodeEnumeration => e.target.c_type
                 | let b: GirNodeBitfield => b.target.c_type
                 | let cb: GirNodeCallback => cb.target.c_type
                 | let a: GirNodeAlias => a.target.c_type
                 end
    pony_type_name(c_type, fallback_qname)

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
    Pony-legal parameter name. Delegates to PonyIdent.safe_param.
    Reserved-word collisions get the prime suffix ("error" ->
    "error'"); primes are legal on parameter and variable bindings
    but NOT on method names (see PonyIdent.safe_method for those).
    """
    PonyIdent.safe_param(gir_name)


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
