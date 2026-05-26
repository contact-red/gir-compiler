// ClosurePlanner — joins ScanResult against GirModel and produces an
// EmitPlan: the closed set of GIR types the generator needs to emit,
// plus the set of method calls user code actually issues against them.
//
// Method-granular emission (since 2026-05-25): T contains only types
// reachable from user code, where "reachable" means:
//
//   (a) types named directly in user source (scan.referenced_names)
//   (b) parameter / return types of constructors of types already
//       in T (because every emitted class gets its constructors)
//   (c) parameter / return types of methods user code actually called
//       on types already in T (looked up via ancestry walk — `set_title`
//       called on Gtk.ApplicationWindow is actually defined on
//       Gtk.Window, but its parameter types still need to be in T)
//
// We do NOT walk every method of every referenced type — that's the
// "type-granular" closure that previously produced 207 types for a
// hello-world. With method-granular closure the same hello-world
// produces ~2-5 types.
//
// 64-iteration safety cap prevents a data bug from spinning forever.

use "collections"
use "gir"
use "scanner"


primitive ClosurePlanner
  fun apply(model: GirModel val, scan: ScanResult val): EmitPlan val =>
    let types = Map[String val, GirNodeRef].create()

    // Phase 1: seed T from scan.referenced_names
    for name in scan.referenced_names.values() do
      match _resolve_pony_name(name, model)
      | (let qname: String val, let node: GirNodeRef) =>
        types(qname) = node
      end
    end

    // Phase 2: build M from scan.method_calls, but only for types
    //          currently in T (we'll re-filter after T finishes growing)
    var calls = _filter_calls(scan.method_calls, types)

    // Phase 3: transitive closure
    var iterations: USize = 0
    var growing: Bool = true
    while growing and (iterations < 64) do
      growing = false
      iterations = iterations + 1

      let frontier = Array[String val]
      for qname in types.keys() do frontier.push(qname) end

      for qname in frontier.values() do
        try
          let node = types(qname)?
          let ns = _namespace_of(node)
          let type_refs = _typed_references_for(node, calls, model)
          for ref_name in type_refs.values() do
            match _resolve_gir_type_name(ref_name, ns, model)
            | (let rqname: String val, let rnode: GirNodeRef) =>
              if not types.contains(rqname) then
                types(rqname) = rnode
                growing = true
              end
            end
          end
        end
      end

      // T grew — re-filter calls so newly-included types' calls
      // also drive next iteration's expansion.
      if growing then
        calls = _filter_calls(scan.method_calls, types)
      end
    end

    // Convert ref map -> val map
    let out = recover iso Map[String val, GirNodeRef] end
    for (k, v) in types.pairs() do out(k) = v end
    let out_calls = recover iso Set[MethodCallRef] end
    for c in calls.values() do out_calls.set(c) end

    EmitPlan._validated(consume out, consume out_calls, scan, iterations)


  fun _filter_calls(
    all_calls: Set[MethodCallRef] val,
    types: Map[String val, GirNodeRef] ref)
    : Set[MethodCallRef] ref
  =>
    """
    Drop call sites whose receiver type isn't in T. The scanner
    already filtered to GIR-known types; this filter accounts for
    the (rare) case where a referenced type is in scan.method_calls
    but didn't survive into T.
    """
    let filtered = Set[MethodCallRef]
    for c in all_calls.values() do
      if types.contains(c.receiver_qname) then filtered.set(c) end
    end
    filtered


  fun _resolve_pony_name(name: String, model: GirModel val)
    : ((String val, GirNodeRef) | None)
  =>
    for ns_name in model.namespaces.keys() do
      if (name.size() > ns_name.size()) and name.at(ns_name, 0) then
        let local: String val = name.substring(ns_name.size().isize())
        let qname: String val = ns_name + "." + local
        match model.resolve(qname)
        | let n: GirNodeRef => return (qname, n)
        end
      end
    end
    None


  fun _resolve_gir_type_name(
    name: String,
    current_ns: NamespaceName,
    model: GirModel val)
    : ((String val, GirNodeRef) | None)
  =>
    if name.size() == 0 then return None end
    if name.contains(".") then
      match model.resolve(name)
      | let n: GirNodeRef => return (name, n)
      end
    else
      let qname: String val = current_ns + "." + name
      match model.resolve(qname)
      | let n: GirNodeRef => return (qname, n)
      end
    end
    None


  fun _namespace_of(node: GirNodeRef): NamespaceName =>
    match node
    | let c: GirNodeClass => c.namespace
    | let i: GirNodeInterface => i.namespace
    | let r: GirNodeRecord => r.namespace
    | let e: GirNodeEnumeration => e.namespace
    | let b: GirNodeBitfield => b.namespace
    | let cb: GirNodeCallback => cb.namespace
    | let a: GirNodeAlias => a.namespace
    end


  fun _typed_references_for(
    node: GirNodeRef,
    calls: Set[MethodCallRef] ref,
    model: GirModel val)
    : Array[String val] val
  =>
    """
    Method-granular collection: for the given node, return type-name
    strings that should drive closure expansion.

      - Classes / records / interfaces: walk constructors always
        (every emitted class can be constructed); walk methods only
        if (qname, method_name) appears in `calls`. Methods may be
        defined on an ancestor — `_find_method_in_ancestry` handles
        the lookup. Properties and signals are deferred (no shape
        yet).
      - Callbacks: walk parameter and return types.
      - Aliases: walk the target type.
      - Enumerations / bitfields: no type references.
    """
    let names = Array[String val]
    let qname = _qname_of(node)
    match node
    | let c: GirNodeClass =>
      let cls = c.target
      for m in cls.constructors.values() do _method_types(m, names) end
      for m_call in calls.values() do
        if m_call.receiver_qname == qname then
          match _find_method_in_ancestry(
            qname, m_call.method_name, model)
          | let m: RawGirMethod val => _method_types(m, names)
          end
        end
      end
      for ifname in cls.implements.values() do names.push(ifname) end
    | let i: GirNodeInterface =>
      let iface = i.target
      for m in iface.constructors.values() do _method_types(m, names) end
      for m_call in calls.values() do
        if m_call.receiver_qname == qname then
          match _find_method_in_ancestry(
            qname, m_call.method_name, model)
          | let m: RawGirMethod val => _method_types(m, names)
          end
        end
      end
      for prereq in iface.prerequisites.values() do names.push(prereq) end
    | let r: GirNodeRecord =>
      let rec = r.target
      for m in rec.constructors.values() do _method_types(m, names) end
      for m_call in calls.values() do
        if m_call.receiver_qname == qname then
          match _find_method_in_ancestry(
            qname, m_call.method_name, model)
          | let m: RawGirMethod val => _method_types(m, names)
          end
        end
      end
    | let _: GirNodeEnumeration => None
    | let _: GirNodeBitfield => None
    | let cb: GirNodeCallback =>
      names.push(cb.target.return_value.typ.name)
      for p in cb.target.parameters.values() do names.push(p.typ.name) end
    | let a: GirNodeAlias =>
      names.push(a.target.target.name)
    end
    // Copy ref -> val for return
    let out = recover iso Array[String val] end
    for n in names.values() do out.push(n) end
    consume out


  fun _qname_of(node: GirNodeRef): String val =>
    match node
    | let c: GirNodeClass => c.namespace + "." + c.target.name
    | let i: GirNodeInterface => i.namespace + "." + i.target.name
    | let r: GirNodeRecord => r.namespace + "." + r.target.name
    | let e: GirNodeEnumeration => e.namespace + "." + e.target.name
    | let b: GirNodeBitfield => b.namespace + "." + b.target.name
    | let cb: GirNodeCallback => cb.namespace + "." + cb.target.name
    | let a: GirNodeAlias => a.namespace + "." + a.target.name
    end


  fun _find_method_in_ancestry(
    qname: String,
    method_name: String,
    model: GirModel val)
    : (RawGirMethod val | None)
  =>
    """
    Look for `method_name` on the type with qname, walking parent
    chain for classes and prerequisite chain for interfaces. Returns
    the first match. Records walk only the record itself (no
    inheritance).
    """
    match model.resolve(qname)
    | let c: GirNodeClass =>
      for m in c.target.methods.values() do
        if m.name == method_name then return m end
      end
      // Also check constructors (rare but legal — user may explicitly
      // call a named constructor like `gtk_label_new_with_mnemonic`)
      for m in c.target.constructors.values() do
        if m.name == method_name then return m end
      end
      if c.target.parent.size() > 0 then
        match _resolve_parent(c.target.parent, c.namespace, model)
        | let pq: String val =>
          return _find_method_in_ancestry(pq, method_name, model)
        end
      end
      None
    | let i: GirNodeInterface =>
      for m in i.target.methods.values() do
        if m.name == method_name then return m end
      end
      for prereq in i.target.prerequisites.values() do
        match _resolve_parent(prereq, i.namespace, model)
        | let pq: String val =>
          match _find_method_in_ancestry(pq, method_name, model)
          | let m: RawGirMethod val => return m
          end
        end
      end
      None
    | let r: GirNodeRecord =>
      for m in r.target.methods.values() do
        if m.name == method_name then return m end
      end
      for m in r.target.constructors.values() do
        if m.name == method_name then return m end
      end
      None
    else
      None
    end


  fun _resolve_parent(
    parent_name: String,
    current_ns: NamespaceName,
    model: GirModel val)
    : (String val | None)
  =>
    """
    GIR's parent attribute is either qualified ("Gio.Application")
    or bare ("Window"). Returns the resolved qname if known.
    """
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


  fun _method_types(m: RawGirMethod val, names: Array[String val] ref) =>
    names.push(m.return_value.typ.name)
    for p in m.parameters.values() do names.push(p.typ.name) end
