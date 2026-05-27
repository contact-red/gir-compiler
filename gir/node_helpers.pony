// NodeHelpers — small accessors that pull common fields off a
// GirNodeRef without each caller writing its own match block.
//
// The seven node kinds (class, interface, record, enumeration,
// bitfield, callback, alias) all carry the same triple — namespace,
// local name, c:type — but only via the inner `target` record. These
// helpers centralize the boilerplate so the emitter and planner can
// say `NodeHelpers.qname_of(n)` instead of repeating a seven-arm
// match.

primitive NodeHelpers
  fun namespace_of(node: GirNodeRef): NamespaceName =>
    match node
    | let c: GirNodeClass => c.namespace
    | let i: GirNodeInterface => i.namespace
    | let r: GirNodeRecord => r.namespace
    | let e: GirNodeEnumeration => e.namespace
    | let b: GirNodeBitfield => b.namespace
    | let cb: GirNodeCallback => cb.namespace
    | let a: GirNodeAlias => a.namespace
    end

  fun local_name_of(node: GirNodeRef): String val =>
    match node
    | let c: GirNodeClass => c.target.name
    | let i: GirNodeInterface => i.target.name
    | let r: GirNodeRecord => r.target.name
    | let e: GirNodeEnumeration => e.target.name
    | let b: GirNodeBitfield => b.target.name
    | let cb: GirNodeCallback => cb.target.name
    | let a: GirNodeAlias => a.target.name
    end

  fun c_type_of(node: GirNodeRef): String val =>
    match node
    | let c: GirNodeClass => c.target.c_type
    | let i: GirNodeInterface => i.target.c_type
    | let r: GirNodeRecord => r.target.c_type
    | let e: GirNodeEnumeration => e.target.c_type
    | let b: GirNodeBitfield => b.target.c_type
    | let cb: GirNodeCallback => cb.target.c_type
    | let a: GirNodeAlias => a.target.c_type
    end

  fun qname_of(node: GirNodeRef): String val =>
    namespace_of(node) + "." + local_name_of(node)
