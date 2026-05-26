// ScanResult — the output of one SourcePackageScanner invocation.
//
// Carries three sets:
//   - referenced_names: every capitalized identifier mentioned in the
//     scanned source. Type names (TK_NOMINAL), expression-position
//     constructor refs, anything whose first character is uppercase.
//     Pre-filter — the closure planner intersects against
//     GirModel.by_qname.
//   - used_packages: every `use "X"` package name.
//   - method_calls: every (receiver-qname, method-name) pair where the
//     receiver was a typed binding resolving to a GIR-known type. The
//     scanner does the GirModel lookup itself, so this set is already
//     filtered to GIR types — Pony built-ins and hand-written runtime
//     types (Env, GtkRuntime, etc.) are dropped during scan.
//
// All three fields are val sets sharing the same identity contract:
// construct once via the validator-side path, then read freely from
// multiple actors.

use "collections"
use "../gir"


class val MethodCallRef is (Hashable & Comparable[MethodCallRef])
  """
  A single (receiver-type-qname, method-name) call-site reference,
  filtered to GIR-known types. "Receiver-type-qname" is in GIR's
  dotted form ("Gtk.ApplicationWindow"), not the Pony spelling, so
  the closure planner can look it up directly via model.resolve().

  Comparable for sorting in the emitter: order is lexicographic on
  (receiver_qname, method_name). Determinism matters because the
  scan and plan store calls in HashSet, which has hash-based
  iteration order.
  """
  let receiver_qname: String val
  let method_name: String val

  new val create(receiver_qname': String val, method_name': String val) =>
    receiver_qname = receiver_qname'
    method_name = method_name'

  fun box hash(): USize =>
    receiver_qname.hash() xor method_name.hash()

  fun box eq(that: MethodCallRef box): Bool =>
    (receiver_qname == that.receiver_qname)
      and (method_name == that.method_name)

  fun box lt(that: MethodCallRef box): Bool =>
    if receiver_qname != that.receiver_qname then
      receiver_qname < that.receiver_qname
    else
      method_name < that.method_name
    end


class val ScanResult
  let referenced_names: Set[String val] val
  let used_packages: Set[String val] val
  let method_calls: Set[MethodCallRef] val

  new val _validated(
    referenced_names': Set[String val] val,
    used_packages': Set[String val] val,
    method_calls': Set[MethodCallRef] val)
  =>
    referenced_names = referenced_names'
    used_packages = used_packages'
    method_calls = method_calls'


type ScanError is
  ( ScanCompileError val
  | ScanEmptyInput val
  | ScanErrorUnannotatedBinding val )


class val ScanErrorUnannotatedBinding
  """
  A let/var/embed/fvar/flet/param binding was declared without a
  type annotation. Per the user-code discipline in DESIGN.md, the
  scanner cannot infer the receiver type of subsequent method calls
  without annotations, so it refuses to silently drop the binding.
  """
  let file: String val
  let line: USize
  let binding_name: String val

  new val create(
    file': String val,
    line': USize,
    binding_name': String val)
  =>
    file = file'
    line = line'
    binding_name = binding_name'

  fun box describe(): String iso^ =>
    let s = recover iso String end
    s.append("unannotated binding `")
    s.append(binding_name)
    s.append("` at ")
    s.append(file)
    s.append(":")
    s.append(line.string())
    s.append(" — generated-type bindings must have a TK_NOMINAL annotation")
    consume s


class val ScanCompileError
  """
  libponyc failed to parse one of the scanned packages. Carries the
  first compiler error message — useful for surfacing syntax errors
  to the user without having to re-run the compiler manually.
  """
  let package_path: String val
  let messages: Array[String val] val

  new val create(
    package_path': String val,
    messages': Array[String val] val)
  =>
    package_path = package_path'
    messages = messages'

  fun box describe(): String iso^ =>
    let s = recover iso String end
    s.append("failed to parse ")
    s.append(package_path)
    s.append(":")
    for m in messages.values() do
      s.append("\n  - ")
      s.append(m)
    end
    consume s


class val ScanEmptyInput
  """
  SourcePackageScanner was handed no packages to scan. Surface as an
  explicit error rather than silently returning an empty ScanResult,
  which would let downstream closure work proceed with no inputs.
  """
  new val create() => None

  fun box describe(): String iso^ =>
    "SourcePackageScanner received no packages".clone()
