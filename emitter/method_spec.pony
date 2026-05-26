// MethodSpec — the validated, normalised form a method takes before
// emission. Computed from a RawGirMethod + emission context (receiver
// type, ancestry chain) and consumed by MethodEmitter to produce the
// final Pony source.
//
// The `outcome` field is either `Emittable` (the spec describes a
// method we know how to emit, including its body shape) or an
// `UnemittableReason val` (the method is in v1's plan but its shape
// or types fall outside what we can produce).

use "../gir"


// ---- PonyType: closed union of types we know how to spell ----

primitive PtBool   primitive PtI8    primitive PtU8    primitive PtI16
primitive PtU16    primitive PtI32   primitive PtU32   primitive PtI64
primitive PtU64    primitive PtF32   primitive PtF64   primitive PtUSize
primitive PtISize  primitive PtNone
class val PtUtf8                  // GIR utf8 → Pony String, with .cstring()
class val PtGObject
  let qname: String val           // "Gtk.Application"
  let pony_type: String val       // "GtkApplication"

  new val create(qname': String val, pony_type': String val) =>
    qname = qname'
    pony_type = pony_type'

class val PtBitfield
  """
  GIR <bitfield>: a set of named bit values OR-combined into a single
  integer at the C ABI. Emitted as a `collections.Flags[(...), U32]`
  type alias plus one primitive per named bit. The Pony-side spelling
  in method signatures is the alias name (e.g. `GioApplicationFlags`);
  at the FFI boundary the underlying integer comes out via `.value()`.
  """
  let qname: String val           // "Gio.ApplicationFlags"
  let pony_type: String val       // "GioApplicationFlags"
  let backing: String val         // "U32" — hardcoded for v1

  new val create(
    qname': String val,
    pony_type': String val,
    backing': String val = "U32")
  =>
    qname = qname'
    pony_type = pony_type'
    backing = backing'

class val PtEnum
  """
  GIR <enumeration>: a closed set of mutually exclusive named integer
  values. Emitted as a Pony union of primitives, each carrying its
  integer via `fun apply(): I32`. The Pony-side spelling in method
  signatures is the alias name (e.g. `GtkOrientation`); at the FFI
  boundary the underlying integer comes out via `.apply()`.
  """
  let qname: String val           // "Gtk.Orientation"
  let pony_type: String val       // "GtkOrientation"
  let backing: String val         // "I32" — hardcoded for v1

  new val create(
    qname': String val,
    pony_type': String val,
    backing': String val = "I32")
  =>
    qname = qname'
    pony_type = pony_type'
    backing = backing'

type PonyType is
  ( PtBool | PtI8 | PtU8 | PtI16 | PtU16 | PtI32 | PtU32 | PtI64 | PtU64
  | PtF32 | PtF64 | PtUSize | PtISize | PtNone | PtUtf8 | PtGObject
  | PtBitfield | PtEnum )


// ---- Body shape: tag for the dispatch table in MethodEmitter ----

primitive ShapeTrivialVoid       // primitives in, no return value
primitive ShapeTrivialReturn     // primitives in, primitive return
primitive ShapeConstructorFloating
primitive ShapeSignalConnect

type MethodShape is
  ( ShapeTrivialVoid
  | ShapeTrivialReturn
  | ShapeConstructorFloating
  | ShapeSignalConnect )


// ---- UnemittableReason: closed vocabulary for skip-stub messages -

primitive UnemittableVariadic
primitive UnemittableUnintrospectable
primitive UnemittableOutParamUnsupported

class val UnemittableUnknownType
  let location: String val        // "parameter `event` of type Gdk.Event"
  let gir_name: String val

  new val create(location': String val, gir_name': String val) =>
    location = location'
    gir_name = gir_name'

class val UnemittableUnsupportedShape
  let detail: String val          // "throws=1 not yet supported"

  new val create(detail': String val) => detail = detail'

class val UnemittableNotFound
  """
  Method appeared in scan.method_calls but couldn't be located on the
  receiver type's ancestry. Either a typo by the user, a signal that
  doesn't match the connect_X pattern, or a method skipped by a more
  specific UnemittableReason on the defining class.
  """
  let method_name: String val

  new val create(method_name': String val) => method_name = method_name'


type UnemittableReason is
  ( UnemittableVariadic
  | UnemittableUnintrospectable
  | UnemittableOutParamUnsupported
  | UnemittableUnknownType val
  | UnemittableUnsupportedShape val
  | UnemittableNotFound val )


// ---- ParamSpec / ReturnSpec / MethodSpec ----

class val ParamSpec
  let name: String val            // safe_param_name applied
  let typ: PonyType
  let gir_name: String val        // raw GIR name (utf8, gint, Window, ...)
                                  // — retained for error messages

  new val create(
    name': String val,
    typ': PonyType,
    gir_name': String val)
  =>
    name = name'
    typ = typ'
    gir_name = gir_name'


class val MethodSpec
  let pony_name: String val       // "set_title", or "create" for ctor
  let c_identifier: String val    // "gtk_window_set_title"
  let library: String val         // "lib:gtk-4"
  let receiver_qname: String val  // qname of the class we're emitting on
                                  // ("Gtk.ApplicationWindow") — same
                                  // even when method is flattened from
                                  // an ancestor
  let inherited_from: (String val | None)
                                  // None when method is on the receiver's
                                  // own class; Some(qname) when flattened
                                  // from an ancestor
  let parameters: Array[ParamSpec val] val
  let return_type: PonyType
  let shape: MethodShape

  new val create(
    pony_name': String val,
    c_identifier': String val,
    library': String val,
    receiver_qname': String val,
    inherited_from': (String val | None),
    parameters': Array[ParamSpec val] val,
    return_type': PonyType,
    shape': MethodShape)
  =>
    pony_name = pony_name'
    c_identifier = c_identifier'
    library = library'
    receiver_qname = receiver_qname'
    inherited_from = inherited_from'
    parameters = parameters'
    return_type = return_type'
    shape = shape'


class val SkippedSpec
  """
  A method that classification could not emit. Carries the
  method_name and receiver qname so the emitter can produce a
  compile_error stub keyed by the call site the user would have
  used. Pony's compile_error inside `ifdef linux or windows or osx`
  is tree-shaken when the method is uncalled, so the stub is free
  unless the user actually references it.
  """
  let method_name: String val
  let receiver_qname: String val
  let reason: UnemittableReason

  new val create(
    method_name': String val,
    receiver_qname': String val,
    reason': UnemittableReason)
  =>
    method_name = method_name'
    receiver_qname = receiver_qname'
    reason = reason'


type MethodOutcome is (MethodSpec val | SkippedSpec val)


// ---- Library map (hardcoded for v1) ----
//
// Maps a GIR namespace to its `use "lib:X"` directive. When the v1
// design surfaced the question of using GIR's `shared-library`
// attribute, we deferred to a hardcoded table — same set of four
// namespaces are loaded for the v1 slice and the names are stable.

primitive LibraryFor
  fun apply(namespace_name: String): String val =>
    match namespace_name
    | "Gtk"     => "lib:gtk-4"
    | "Gio"     => "lib:gio-2.0"
    | "GLib"    => "lib:glib-2.0"
    | "GObject" => "lib:gobject-2.0"
    else
      // Unknown namespace; emit empty so we don't add a bogus
      // `use "lib:"` line. Real v1.x will read shared-library from
      // the loaded GIR.
      ""
    end
