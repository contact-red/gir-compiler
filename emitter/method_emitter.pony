// MethodEmitter — turns a MethodSpec into Pony source: one `use @`
// FFI declaration plus one method body. The four v1 shapes are
// `ShapeTrivialVoid`, `ShapeTrivialReturn`, `ShapeConstructorFloating`,
// `ShapeSignalConnect`. Anything outside this catalog comes through
// `classify_*` as an `UnemittableReason` and emits a `compile_error`
// stub instead, so the user gets a useful error at the call site.
//
// Method emission has two entry points:
//
//   - classify_method(receiver_qname, method_name, model) →
//       MethodOutcome
//     for entries in `EmitPlan.method_calls`
//
//   - classify_constructor(receiver_node, raw_ctor) →
//       MethodOutcome
//     called once per constructor on every type in T

use "../doc_translate"
use "../gir"


primitive MethodEmitter
  fun classify_method(
    receiver_qname: String val,
    method_name: String val,
    model: GirModel val)
    : MethodOutcome
  =>
    """
    Find the method in the receiver type's ancestry; classify its
    shape. Falls through to `_classify_signal` if a connect_X method
    name doesn't match any real method.
    """
    match _find_in_ancestry(receiver_qname, method_name, model)
    | (let m: RawGirMethod val,
        let owner_qname: String val,
        let owner_ns: String val) =>
      _wrap_skip(receiver_qname, method_name, m.doc,
        _classify_raw(m, receiver_qname, owner_qname, owner_ns,
          method_name, model))
    else
      // Not a method — maybe a connect_X for a signal.
      _wrap_skip(receiver_qname, method_name, "",
        _classify_signal(receiver_qname, method_name, model))
    end


  fun _wrap_skip(
    receiver_qname: String val,
    method_name: String val,
    doc: String val,
    outcome: (MethodSpec val | UnemittableReason))
    : MethodOutcome
  =>
    """
    classify_raw / classify_signal return the inner (MethodSpec |
    UnemittableReason). Wrap the reason side with method/receiver
    context so the emitter can produce a compile_error stub keyed
    by name. `doc` carries any GIR <doc> text we want preserved on
    the skip stub so docs-mode generation can still show users what
    the missing method does.

    The method name is routed through PonyIdent.safe_method before
    reaching SkippedSpec — without this, skip stubs for reserved-
    word method names (e.g. `fun ref error()`) emit invalid Pony
    source, same way MethodSpec names had to be munged.
    """
    match outcome
    | let s: MethodSpec val => s
    | let r: UnemittableReason =>
      SkippedSpec(PonyIdent.safe_method(method_name), receiver_qname, r, doc)
    end


  fun classify_constructor(
    receiver_qname: String val,
    receiver_ns: String val,
    raw_ctor: RawGirMethod val,
    model: GirModel val)
    : MethodOutcome
  =>
    """
    Constructors classify as ShapeConstructorFloating for v1 (every
    GObject-derived class returns a floating ref from its `_new` and
    we sink immediately via GObjectHandle.adopt_floating). Records
    and types not descending from GInitiallyUnowned are
    UnemittableUnsupportedShape until follow-up work.
    """
    _wrap_skip(receiver_qname, "create", raw_ctor.doc,
      _classify_raw(
        raw_ctor,
        receiver_qname,
        receiver_qname,
        receiver_ns,
        "create",
        model))


  // ---- Classification helpers ----

  fun _classify_raw(
    m: RawGirMethod val,
    receiver_qname: String val,
    owner_qname: String val,
    owner_ns: String val,
    pony_name: String val,
    model: GirModel val)
    : (MethodSpec val | UnemittableReason)
  =>
    // Build params + return; bail early on any unrepresentable type.
    let params = recover iso Array[ParamSpec val] end
    for p in m.parameters.values() do
      let loc: String val = "parameter `" + p.name + "`"
      match _pony_type_for(p.typ.name, owner_ns, loc, model)
      | let t: PonyType =>
        params.push(ParamSpec(
          TypeNaming.safe_param_name(p.name),
          t,
          p.typ.name))
      | let u: UnemittableReason => return u
      end
    end

    let return_type =
      match _pony_type_for(m.return_value.typ.name, owner_ns,
        "return value", model)
      | let t: PonyType => t
      | let u: UnemittableReason => return u
      end

    // Pick body shape.
    let shape: MethodShape =
      match m.kind
      | RawGirMethodKindConstructor => ShapeConstructorFloating
      else
        match return_type
        | PtNone => ShapeTrivialVoid
        else ShapeTrivialReturn
        end
      end

    MethodSpec(
      PonyIdent.safe_method(pony_name),
      m.c_identifier,
      LibraryFor(owner_ns),
      receiver_qname,
      if owner_qname == receiver_qname then None else owner_qname end,
      consume params,
      return_type,
      shape,
      m.doc)


  fun _pony_type_for(
    gir_name: String,
    owner_ns: String,
    location: String val,
    model: GirModel val)
    : (PonyType | UnemittableReason)
  =>
    """
    Map a GIR type name to a v1 PonyType. Resolves object-typed names
    against the loaded model so bitfields land as PtBitfield, classes
    / interfaces / records as PtGObject, and enumerations + other
    kinds as UnemittableUnknownType (no PtEnum yet — adds in a
    follow-up).
    """
    // GIR array sentinel — emitted by the loader as "array<inner>"
    // when GIR wraps a <type> in <array>. We don't have a v1 array
    // shape yet (the FFI marshalling is non-trivial), so any method
    // with an array parameter or return type skips. The detail
    // message keeps the inner type visible for triage.
    if gir_name.at("array<", 0) then
      return UnemittableUnsupportedShape(
        gir_name + " not yet supported (" + location + ")")
    end
    match gir_name
    | "none" => PtNone
    | "gboolean" => PtBool
    | "gint8" => PtI8
    | "guint8" => PtU8
    | "gint16" => PtI16
    | "guint16" => PtU16
    | "gint" | "gint32" => PtI32
    | "guint" | "guint32" => PtU32
    | "glong" | "gint64" => PtI64
    | "gulong" | "guint64" => PtU64
    | "gfloat" => PtF32
    | "gdouble" => PtF64
    | "gsize" => PtUSize
    | "gssize" => PtISize
    | "utf8" => PtUtf8
    | "varargs" => UnemittableVariadic
    else
      // Object reference — resolve via the model to distinguish
      // bitfields (PtBitfield) from object types (PtGObject).
      match _resolve_object_type(gir_name, owner_ns)
      | (let qname: String val, let pony_ty: String val) =>
        match model.resolve(qname)
        | let _: GirNodeBitfield => PtBitfield(qname, pony_ty)
        | let _: GirNodeEnumeration => PtEnum(qname, pony_ty)
        | let _: GirNodeClass => PtGObject(qname, pony_ty)
        | let _: GirNodeInterface => PtGObject(qname, pony_ty)
        | let _: GirNodeRecord => PtGObject(qname, pony_ty)
        | None =>
          // Not in the model — could be a type from an unloaded
          // namespace; treat as opaque GObject pointer so the FFI
          // still works (caller will see a generated marker type
          // they can interact with via raw pointer if needed).
          PtGObject(qname, pony_ty)
        else
          // Callbacks and aliases — don't yet have a v1 type
          // spelling. Surface as a skip rather than emit broken
          // source.
          UnemittableUnknownType(location, gir_name)
        end
      else
        UnemittableUnknownType(location, gir_name)
      end
    end


  fun _resolve_object_type(
    gir_name: String,
    owner_ns: String)
    : ((String val, String val) | None)
  =>
    """
    "Window" + owner_ns="Gtk" → ("Gtk.Window", "GtkWindow")
    "Gio.Application" → ("Gio.Application", "GioApplication")
    """
    if gir_name.size() == 0 then return None end
    if gir_name.contains(".") then
      try
        let idx = gir_name.find(".")?
        let ns: String val = gir_name.substring(0, idx)
        let local: String val = gir_name.substring(idx + 1)
        return (gir_name, ns + local)
      end
      None
    else
      (owner_ns + "." + gir_name, owner_ns + gir_name)
    end


  fun _find_in_ancestry(
    qname: String,
    method_name: String,
    model: GirModel val)
    : ((RawGirMethod val, String val, String val) | None)
  =>
    """
    Returns (method, owning_qname, owning_namespace) for the first
    matching method along the ancestry walk. None if no class /
    interface / record / prerequisite in the chain owns it.
    """
    match model.resolve(qname)
    | let c: GirNodeClass =>
      for m in c.target.methods.values() do
        if m.name == method_name then
          return (m, c.namespace + "." + c.target.name, c.namespace)
        end
      end
      if c.target.parent.size() > 0 then
        match _resolve_parent(c.target.parent, c.namespace, model)
        | let pq: String val =>
          return _find_in_ancestry(pq, method_name, model)
        end
      end
      None
    | let i: GirNodeInterface =>
      for m in i.target.methods.values() do
        if m.name == method_name then
          return (m, i.namespace + "." + i.target.name, i.namespace)
        end
      end
      for prereq in i.target.prerequisites.values() do
        match _resolve_parent(prereq, i.namespace, model)
        | let pq: String val =>
          match _find_in_ancestry(pq, method_name, model)
          | (let m: RawGirMethod val,
              let owner_q: String val,
              let owner_n: String val) =>
            return (m, owner_q, owner_n)
          end
        end
      end
      None
    | let r: GirNodeRecord =>
      for m in r.target.methods.values() do
        if m.name == method_name then
          return (m, r.namespace + "." + r.target.name, r.namespace)
        end
      end
      None
    else
      None
    end


  fun _resolve_parent(
    parent_name: String,
    current_ns: String,
    model: GirModel val)
    : (String val | None)
  =>
    if parent_name.contains(".") then
      match model.resolve(parent_name)
      | let _: GirNodeRef => return parent_name
      end
    else
      let qname: String val = current_ns + "." + parent_name
      match model.resolve(qname)
      | let _: GirNodeRef => return qname
      end
    end
    None


  // ---- Signal classification (connect_X methods) ----

  fun _classify_signal(
    receiver_qname: String val,
    method_name: String val,
    model: GirModel val)
    : (MethodSpec val | UnemittableReason)
  =>
    """
    `connect_close_request` → look up signal `close-request` on the
    receiver's class or ancestry. For v1 only `close-request` is
    wired through the runtime; everything else is
    UnemittableUnsupportedShape.
    """
    if not method_name.at("connect_", 0) then
      return UnemittableNotFound(method_name)
    end

    // For v1 only one wired-up signal.
    if method_name != "connect_close_request" then
      return UnemittableUnsupportedShape(
        "signal `" + method_name + "` not wired into v1 runtime")
    end

    // Confirm the signal exists somewhere in the ancestry — protects
    // against `connect_close_request` being called on a type that
    // doesn't actually emit close-request.
    if not _signal_exists_in_ancestry(
      receiver_qname, "close-request", model)
    then
      return UnemittableNotFound(method_name)
    end

    MethodSpec(
      method_name,
      "",                           // no FFI symbol — body delegates to runtime
      "",                           // no `use "lib:..."` from this method
      receiver_qname,
      None,
      recover val Array[ParamSpec val] end,
      PtNone,
      ShapeSignalConnect,
      "")                           // signal-connect helpers have no GIR doc



  fun _signal_exists_in_ancestry(
    qname: String,
    signal_name: String,
    model: GirModel val)
    : Bool
  =>
    match model.resolve(qname)
    | let c: GirNodeClass =>
      for s in c.target.signals.values() do
        if s.name == signal_name then return true end
      end
      if c.target.parent.size() > 0 then
        match _resolve_parent(c.target.parent, c.namespace, model)
        | let pq: String val =>
          return _signal_exists_in_ancestry(pq, signal_name, model)
        end
      end
      false
    | let i: GirNodeInterface =>
      for s in i.target.signals.values() do
        if s.name == signal_name then return true end
      end
      false
    else
      false
    end


  // ---- Emission ----

  fun emit(
    outcome: MethodOutcome,
    translate_ctx: (TranslateContext val | None) = None)
    : String val
  =>
    match outcome
    | let spec: MethodSpec val =>
      match spec.shape
      | ShapeTrivialVoid         => _emit_trivial_void(spec, translate_ctx)
      | ShapeTrivialReturn       => _emit_trivial_return(spec, translate_ctx)
      | ShapeConstructorFloating => _emit_constructor_floating(spec, translate_ctx)
      | ShapeSignalConnect       => _emit_signal_connect(spec, translate_ctx)
      end
    | let s: SkippedSpec val => _emit_skip_stub(s, translate_ctx)
    end


  fun emit_ffi_use(spec: MethodSpec val): String val =>
    """
    The `use @symbol[RetCType](args...)` line that must appear at the
    top of the generated file for this method. Returns empty for
    shapes that don't generate FFI calls (signal-connect).
    """
    if spec.c_identifier.size() == 0 then return "" end

    let buf = recover iso String end
    buf.append("use @")
    buf.append(spec.c_identifier)
    buf.append("[")
    buf.append(_ffi_type(spec.return_type))
    buf.append("](")

    var first: Bool = true
    match spec.shape
    | ShapeConstructorFloating => None
    else
      // Instance methods take `_h.raw()` as their first FFI arg.
      buf.append("self: Pointer[U8] tag")
      first = false
    end
    for p in spec.parameters.values() do
      if not first then buf.append(", ") end
      buf.append(p.name)
      buf.append(": ")
      buf.append(_ffi_type(p.typ))
      first = false
    end
    buf.append(")\n")
    consume buf


  fun _emit_trivial_void(
    spec: MethodSpec val,
    translate_ctx: (TranslateContext val | None))
    : String val
  =>
    let buf = recover iso String end
    buf.append("\n  fun ref ")
    buf.append(spec.pony_name)
    buf.append("(")
    buf.append(_pony_params_str(spec.parameters))
    buf.append(") =>\n")
    buf.append(DocstringWriter(spec.doc, translate_ctx, "    "))
    buf.append("    @")
    buf.append(spec.c_identifier)
    buf.append("(_h.raw()")
    for p in spec.parameters.values() do
      buf.append(", ")
      buf.append(_marshal_arg(p))
    end
    buf.append(")\n")
    consume buf


  fun _emit_trivial_return(
    spec: MethodSpec val,
    translate_ctx: (TranslateContext val | None))
    : String val
  =>
    let buf = recover iso String end
    buf.append("\n  fun ref ")
    buf.append(spec.pony_name)
    buf.append("(")
    buf.append(_pony_params_str(spec.parameters))
    buf.append("): ")
    buf.append(_pony_type_decl(spec.return_type))
    buf.append(" =>\n")
    buf.append(DocstringWriter(spec.doc, translate_ctx, "    "))
    buf.append("    @")
    buf.append(spec.c_identifier)
    buf.append("(_h.raw()")
    for p in spec.parameters.values() do
      buf.append(", ")
      buf.append(_marshal_arg(p))
    end
    buf.append(")\n")
    consume buf


  fun _emit_constructor_floating(
    spec: MethodSpec val,
    translate_ctx: (TranslateContext val | None))
    : String val
  =>
    let buf = recover iso String end
    buf.append("\n  new create(")
    buf.append(_pony_params_str(spec.parameters))
    buf.append(") =>\n")
    buf.append(DocstringWriter(spec.doc, translate_ctx, "    "))
    buf.append("    let raw = @")
    buf.append(spec.c_identifier)
    buf.append("(")
    var first: Bool = true
    for p in spec.parameters.values() do
      if not first then buf.append(", ") end
      buf.append(_marshal_arg(p))
      first = false
    end
    buf.append(")\n    _h = GObjectHandle.adopt_floating(raw)\n")

    // Source `_runtime` from the first GObject parameter (if any).
    var runtime_source: String = ""
    for p in spec.parameters.values() do
      match p.typ
      | let _: PtGObject =>
        runtime_source = p.name + "._runtime_ref()"
        break
      end
    end
    if runtime_source.size() > 0 then
      buf.append("    _runtime = ")
      buf.append(runtime_source)
      buf.append("\n")
    end
    consume buf


  fun _emit_signal_connect(
    spec: MethodSpec val,
    translate_ctx: (TranslateContext val | None))
    : String val
  =>
    // For v1 only `connect_close_request` is wired.
    let buf = recover iso String end
    buf.append("\n  fun ref ")
    buf.append(spec.pony_name)
    buf.append("(handler: CloseRequestHandler) =>\n")
    buf.append(DocstringWriter(spec.doc, translate_ctx, "    "))
    buf.append("    _runtime._register_close_request(_h.raw(), handler)\n")
    consume buf


  fun _emit_skip_stub(
    s: SkippedSpec val,
    translate_ctx: (TranslateContext val | None))
    : String val
  =>
    """
    Emit a method declaration that fails at the call site with a
    useful compile_error message. The body sits inside `ifdef linux
    or windows or osx` so Pony's tree-shaker elides it unless the
    method is actually called (verified empirically — uncalled
    methods don't trigger their compile_error). Wrong-arity calls
    will get the ordinary `wrong number of arguments` error from
    ponyc.

    The docstring is emitted before the ifdef so it survives both
    docs-mode rendering (visible to readers on the docs site) and
    compile-mode tree-shaking (the doc is a string literal Pony
    keeps as method documentation).
    """
    let buf = recover iso String end
    buf.append("\n  fun ref ")
    buf.append(s.method_name)
    buf.append("() =>\n")
    buf.append(DocstringWriter(s.doc, translate_ctx, "    "))
    buf.append("    ifdef linux or windows or osx then\n")
    buf.append("      compile_error \"")
    buf.append(s.receiver_qname)
    buf.append(".")
    buf.append(s.method_name)
    buf.append(": ")
    buf.append(_describe(s.reason))
    buf.append("\"\n")
    buf.append("    end\n")
    consume buf


  fun _describe(u: UnemittableReason): String val =>
    match u
    | let _: UnemittableVariadic => "variadic"
    | let _: UnemittableUnintrospectable => "introspectable=0"
    | let _: UnemittableOutParamUnsupported => "out parameter not yet supported"
    | let x: UnemittableUnknownType val =>
      "unknown GIR type `" + x.gir_name + "` (" + x.location + ")"
    | let x: UnemittableUnsupportedShape val =>
      "unsupported shape: " + x.detail
    | let x: UnemittableNotFound val =>
      "no method `" + x.method_name + "` found in ancestry"
    end


  // ---- Type spelling: Pony parameter declarations & FFI types ----

  fun _pony_params_str(params: Array[ParamSpec val] val): String val =>
    let buf = recover iso String end
    var first: Bool = true
    for p in params.values() do
      if not first then buf.append(", ") end
      buf.append(p.name)
      buf.append(": ")
      buf.append(_pony_type_decl(p.typ))
      first = false
    end
    consume buf


  fun _pony_type_decl(t: PonyType): String val =>
    """
    Pony-side type spelling for a method-signature position.
    """
    match t
    | PtBool => "Bool"
    | PtI8 => "I8"
    | PtU8 => "U8"
    | PtI16 => "I16"
    | PtU16 => "U16"
    | PtI32 => "I32"
    | PtU32 => "U32"
    | PtI64 => "I64"
    | PtU64 => "U64"
    | PtF32 => "F32"
    | PtF64 => "F64"
    | PtUSize => "USize"
    | PtISize => "ISize"
    | PtNone => "None"
    | let _: PtUtf8 => "String"
    | let g: PtGObject => g.pony_type + " box"
    | let b: PtBitfield => b.pony_type + " box"
    | let e: PtEnum => e.pony_type
    end


  fun _ffi_type(t: PonyType): String val =>
    """
    C-side ABI spelling for the `use @` FFI declaration.
    """
    match t
    | PtBool => "Bool"
    | PtI8 => "I8"
    | PtU8 => "U8"
    | PtI16 => "I16"
    | PtU16 => "U16"
    | PtI32 => "I32"
    | PtU32 => "U32"
    | PtI64 => "I64"
    | PtU64 => "U64"
    | PtF32 => "F32"
    | PtF64 => "F64"
    | PtUSize => "USize"
    | PtISize => "ISize"
    | PtNone => "None"
    | let _: PtUtf8 => "Pointer[U8] tag"
    | let _: PtGObject => "Pointer[U8] tag"
    | let b: PtBitfield => b.backing
    | let e: PtEnum => e.backing
    end


  fun _marshal_arg(p: ParamSpec val): String val =>
    """
    At a call site, the Pony-side identifier may need wrapping
    before passing to FFI: `t.cstring()` for utf8, `o._handle().raw()`
    for GObject, `f.value()` for bitfield, raw passthrough for
    primitives.
    """
    match p.typ
    | let _: PtUtf8 => p.name + ".cstring()"
    | let _: PtGObject => p.name + "._handle().raw()"
    | let _: PtBitfield => p.name + ".value()"
    | let _: PtEnum => p.name + ".apply()"
    else p.name
    end
