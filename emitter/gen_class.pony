// GenClass — generate a Pony source file for a GIR <class>.
//
// File shape:
//   // generated header
//   use "gobject_runtime"
//   use "lib:<library>"            (one per library actually used)
//   use @c_identifier[ret](...)    (one per emitted method/constructor)
//
//   class <PonyName>
//     let _h: GObjectHandle box
//     let _runtime: GtkRuntime tag
//
//     new _wrap(h: GObjectHandle box, runtime: GtkRuntime tag) =>
//       _h = h
//       _runtime = runtime
//
//     fun box _handle(): GObjectHandle box => _h
//     fun box _runtime_ref(): GtkRuntime tag => _runtime
//
//     <constructors>           — every constructor in the GIR class,
//                                except those on the hand-curated
//                                suppress list
//     <flattened methods>      — one per (this_qname, method_name) in
//                                plan.method_calls; the method is
//                                located via MethodEmitter's ancestry
//                                walk so set_title (defined on
//                                Gtk.Window) lands on Gtk.ApplicationWindow
//                                when the user called it there
//
// Methods or constructors that MethodEmitter cannot classify emit a
// `// skipped: …` comment instead. The class compiles either way;
// the user can `make scratch_emit && ponyc gen/<ns>/` to check.

use "collections"
use "../doc_translate"
use "../gir"
use "../planner"
use "../scanner"


primitive SuppressedConstruction
  fun apply(qname: String): Bool =>
    """
    Hand-curated suppress list. Types whose construction must NOT
    be exposed as a public Pony constructor because they're tied to
    runtime infrastructure (pinned-thread initialization, etc.) and
    have to come through GtkRuntime instead.

    Per the Stage-2 evaluation (adversarial F3) this should
    eventually be derived from GIR structure rather than hand-
    curated; that's deferred.
    """
    match qname
    | "Gtk.Application" => true
    else false
    end


primitive GenClass
  fun apply(
    qname: String val,
    node: GirNodeClass,
    plan: EmitPlan val,
    model: GirModel val,
    translate_ctx: (TranslateContext val | None) = None)
    : String val
  =>
    let pony_name: String val = TypeNaming.pony_type_name(node.target.c_type, qname)
    let receiver_ns: String val = node.namespace

    // Sort method calls by (receiver_qname, method_name) so emit
    // order is reproducible across runs. The plan's HashSet has
    // non-deterministic iteration order.
    let sorted_calls = Array[MethodCallRef]
    for call in plan.method_calls.values() do
      if call.receiver_qname == qname then
        sorted_calls.push(call)
      end
    end
    Sort[Array[MethodCallRef], MethodCallRef](sorted_calls)

    // First pass: figure out the Pony name every constructor and
    // method will land on so the classifier can disambiguate
    // parameter names that would otherwise shadow them. Also include
    // the names of the synthetic fields and methods that gen_class
    // itself emits (_h, _runtime, _wrap, _handle, _runtime_ref) so
    // params don't clash with those either.
    let class_member_names: Set[String val] iso = recover iso
      let s = Set[String val]
      s.set("_h")
      s.set("_runtime")
      s.set("_wrap")
      s.set("_handle")
      s.set("_runtime_ref")
      s
    end
    if not SuppressedConstruction(qname) then
      for ctor in node.target.constructors.values() do
        class_member_names.set(
          PonyIdent.safe_method(MethodEmitter.constructor_pony_name(ctor.name)))
      end
    end
    for call in sorted_calls.values() do
      class_member_names.set(PonyIdent.safe_method(call.method_name))
    end
    let member_names: Set[String val] val = consume class_member_names

    // -- Classify constructors and methods upfront so we can
    //    collect FFI declarations and library directives.
    let outcomes: Array[MethodOutcome] = Array[MethodOutcome]
    let libraries: Set[String val] = Set[String val]

    if not SuppressedConstruction(qname) then
      for ctor in node.target.constructors.values() do
        outcomes.push(
          MethodEmitter.classify_constructor(
            qname, receiver_ns, ctor, model, member_names))
      end
    end

    for call in sorted_calls.values() do
      outcomes.push(
        MethodEmitter.classify_method(
          qname, call.method_name, model, member_names))
    end

    for o_lib in outcomes.values() do
      match o_lib
      | let s: MethodSpec val =>
        if s.library.size() > 0 then libraries.set(s.library) end
      | let _: SkippedSpec val => None  // skip stubs have no FFI lib
      end
    end

    // Collect every other GIR namespace whose types appear in this
    // class's emitted methods (parameters and return types). Each
    // foreign namespace needs a sibling-package `use` directive so
    // ponyc can find the referenced type. PtGObject / PtBitfield /
    // PtEnum carry their qname; everything else is primitive and
    // doesn't introduce a package dependency.
    let foreign_namespaces: Set[NamespaceName] = Set[NamespaceName]
    for o_ns in outcomes.values() do
      match o_ns
      | let s: MethodSpec val =>
        _add_foreign_ns(s.return_type, receiver_ns, foreign_namespaces)
        for p in s.parameters.values() do
          _add_foreign_ns(p.typ, receiver_ns, foreign_namespaces)
        end
      end
    end

    // -- Build the file ----------
    let buf = recover iso String end
    buf.append("// generated by gtk4-bind for ")
    buf.append(qname)
    buf.append("\n")
    buf.append("// GIR class: c_type=")
    buf.append(node.target.c_type)
    if node.target.parent.size() > 0 then
      buf.append(", parent=")
      buf.append(node.target.parent)
    end
    buf.append("\n\n")

    buf.append("use \"../gobject_runtime\"\n")
    // Sibling-package imports for foreign GIR namespaces.
    let sorted_foreign = Array[NamespaceName]
    for ns in foreign_namespaces.values() do sorted_foreign.push(ns) end
    Sort[Array[NamespaceName], NamespaceName](sorted_foreign)
    for ns in sorted_foreign.values() do
      buf.append("use \"../")
      buf.append(ns.lower())
      buf.append("\"\n")
    end
    // Sort library directives lexicographically.
    let sorted_libs = Array[String val]
    for lib in libraries.values() do sorted_libs.push(lib) end
    Sort[Array[String val], String val](sorted_libs)
    for lib in sorted_libs.values() do
      buf.append("use \"")
      buf.append(lib)
      buf.append("\"\n")
    end
    buf.append("\n")

    for o_ffi in outcomes.values() do
      match o_ffi
      | let s: MethodSpec val =>
        buf.append(MethodEmitter.emit_ffi_use(s))
      | let _: SkippedSpec val => None  // skip stubs have no FFI use line
      end
    end
    buf.append("\n")

    buf.append("class ")
    buf.append(pony_name)
    buf.append("\n")
    buf.append(DocstringWriter(node.target.doc, translate_ctx, "  "))
    buf.append("  let _h: GObjectHandle box\n")
    buf.append("  let _runtime: PinnedRuntime tag\n\n")
    buf.append("  new _wrap(h: GObjectHandle box, runtime: PinnedRuntime tag) =>\n")
    buf.append("    _h = h\n")
    buf.append("    _runtime = runtime\n\n")
    buf.append("  fun box _handle(): GObjectHandle box => _h\n")
    buf.append("  fun box _runtime_ref(): PinnedRuntime tag => _runtime\n")

    for o_emit in outcomes.values() do
      buf.append(MethodEmitter.emit(o_emit, translate_ctx))
    end
    consume buf


  fun _add_foreign_ns(
    t: PonyType,
    receiver_ns: NamespaceName,
    out: Set[NamespaceName] ref)
  =>
    """
    If `t` is an object-typed reference (PtGObject, PtBitfield,
    PtEnum) and its declaring namespace differs from `receiver_ns`,
    add that namespace to `out`. Primitives and PtNone don't carry
    a namespace and are skipped.
    """
    let qname = match t
                | let g: PtGObject val => g.qname
                | let b: PtBitfield val => b.qname
                | let e: PtEnum val => e.qname
                else ""
                end
    if qname.size() == 0 then return end
    try
      let idx = qname.find(".")?
      let ns = qname.substring(0, idx)
      let ns_str: NamespaceName = consume ns
      if ns_str != receiver_ns then out.set(ns_str) end
    end
