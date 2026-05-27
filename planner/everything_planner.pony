// EverythingPlanner — produces an EmitPlan that covers the entire
// loaded GIR model. Sibling of ClosurePlanner; differs only in the
// scope of what gets emitted. ClosurePlanner does method-granular
// reachability analysis from user source; EverythingPlanner emits
// every type and every method in every loaded namespace.
//
// Used by the gir-docs binary: documentation consumers need the
// whole API surface, not just whatever the calling application
// happens to touch.
//
// The resulting EmitPlan carries an empty ScanResult — there is no
// scanned source to speak of — and the emitter consumes it the same
// way it consumes a closure-mode plan.

use "collections"
use "../gir"
use "../scanner"


primitive EverythingPlanner
  fun apply(model: GirModel val): EmitPlan val =>
    """
    Walk every namespace in `model` and produce a plan that emits
    every type. Every method, constructor, and function declared
    on those types is added to `method_calls` so the emitter
    generates bindings (or skip stubs) for the entire API surface.

    The emitter's MethodEmitter handles ancestry walks for inherited
    methods; we only register methods that exist on this type's own
    definition so the emitter doesn't double-emit.

    Other node kinds (enum, bitfield, callback, alias) contribute no
    method calls; the emitter generates them from their type-level
    shape alone.
    """
    let types = recover iso Map[String val, GirNodeRef] end
    let method_calls = recover iso Set[MethodCallRef] end

    for (qname, node) in model.by_qname.pairs() do
      types(qname) = node
      match node
      | let c: GirNodeClass =>
        for m in c.target.constructors.values() do
          method_calls.set(MethodCallRef(qname, m.name))
        end
        for m in c.target.methods.values() do
          method_calls.set(MethodCallRef(qname, m.name))
        end
      | let i: GirNodeInterface =>
        for m in i.target.constructors.values() do
          method_calls.set(MethodCallRef(qname, m.name))
        end
        for m in i.target.methods.values() do
          method_calls.set(MethodCallRef(qname, m.name))
        end
      | let r: GirNodeRecord =>
        for m in r.target.constructors.values() do
          method_calls.set(MethodCallRef(qname, m.name))
        end
        for m in r.target.methods.values() do
          method_calls.set(MethodCallRef(qname, m.name))
        end
      end
    end

    EmitPlan._validated(
      consume types,
      consume method_calls,
      ScanResult.empty(),
      0)
