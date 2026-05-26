// EmitPlan — the output of ClosurePlanner.
//
// Tells the emitter exactly which GIR types to generate. For v1 with
// strategy (a) "generate all methods per referenced type", a plan is
// just the set of qnames to emit, each paired with its GirNodeRef so
// the emitter can dispatch on node kind without doing a second
// model.resolve(). The scan result is passed through for use_packages
// context (the emitter may want to know which packages need to exist
// on disk for the user's source to compile).

use "collections"
use "../gir"
use "../scanner"


class val EmitPlan
  let types: Map[String val, GirNodeRef] val
  let method_calls: Set[MethodCallRef] val
  let scan: ScanResult val
  let iterations: USize     // closure iteration count, useful for debug

  new val _validated(
    types': Map[String val, GirNodeRef] val,
    method_calls': Set[MethodCallRef] val,
    scan': ScanResult val,
    iterations': USize)
  =>
    types = types'
    method_calls = method_calls'
    scan = scan'
    iterations = iterations'
