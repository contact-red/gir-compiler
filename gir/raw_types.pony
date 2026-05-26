// Additional raw GIR types: interfaces, records, enumerations,
// bitfields, callbacks, aliases, plus signals/properties for classes
// and interfaces. Same conventions as raw.pony — class val,
// constructor-takes-everything, no validation.


class val RawGirInterface
  """
  A GIR <interface> element. Like <class> but has no `parent`
  (interfaces can inherit from other interfaces via <prerequisite>
  children instead). Captures methods, properties, and signals
  defined on the interface.
  """
  let name: String val
  let c_type: String val
  let prerequisites: Array[String val] val
  let constructors: Array[RawGirMethod val] val
  let methods: Array[RawGirMethod val] val
  let properties: Array[RawGirProperty val] val
  let signals: Array[RawGirSignal val] val

  new val create(
    name': String val,
    c_type': String val,
    prerequisites': Array[String val] val,
    constructors': Array[RawGirMethod val] val,
    methods': Array[RawGirMethod val] val,
    properties': Array[RawGirProperty val] val,
    signals': Array[RawGirSignal val] val)
  =>
    name = name'
    c_type = c_type'
    prerequisites = prerequisites'
    constructors = constructors'
    methods = methods'
    properties = properties'
    signals = signals'


class val RawGirRecord
  """
  A GIR <record> element. C structs / opaque types. Carries
  name + c_type plus any methods/constructors GIR declares on it.
  Fields are recorded as a count for now; full field modeling
  (with types and offsets) is deferred until something actually
  needs to read them — most consumers use records as opaque
  pointers via constructor + accessor methods.
  """
  let name: String val
  let c_type: String val
  let disguised: Bool
  let opaque: Bool
  let constructors: Array[RawGirMethod val] val
  let methods: Array[RawGirMethod val] val

  new val create(
    name': String val,
    c_type': String val,
    disguised': Bool,
    opaque': Bool,
    constructors': Array[RawGirMethod val] val,
    methods': Array[RawGirMethod val] val)
  =>
    name = name'
    c_type = c_type'
    disguised = disguised'
    opaque = opaque'
    constructors = constructors'
    methods = methods'


class val RawGirEnumeration
  """
  A GIR <enumeration> element. A closed set of named values.
  GIR also exposes <bitfield> with the same shape; we keep them
  as distinct types because their emission rules differ (enums
  become Pony unions of primitives; bitfields become class val
  wrappers with or/and combinators).
  """
  let name: String val
  let c_type: String val
  let members: Array[RawGirMember val] val

  new val create(
    name': String val,
    c_type': String val,
    members': Array[RawGirMember val] val)
  =>
    name = name'
    c_type = c_type'
    members = members'


class val RawGirBitfield
  """
  A GIR <bitfield> element. Flags semantics — members are powers
  of two and may be OR-combined. Same XML shape as enumeration;
  separate Pony type because the generator emits them differently.
  """
  let name: String val
  let c_type: String val
  let members: Array[RawGirMember val] val

  new val create(
    name': String val,
    c_type': String val,
    members': Array[RawGirMember val] val)
  =>
    name = name'
    c_type = c_type'
    members = members'


class val RawGirMember
  """
  A <member> child of an <enumeration> or <bitfield>. Has a GIR
  name (e.g., "horizontal"), a C-side identifier (e.g.,
  "GTK_ORIENTATION_HORIZONTAL"), and a string value. Value is a
  string because GIR encodes integer literals as decimal text;
  the validator will parse them to an integer type.
  """
  let name: String val
  let value: String val
  let c_identifier: String val

  new val create(
    name': String val,
    value': String val,
    c_identifier': String val)
  =>
    name = name'
    value = value'
    c_identifier = c_identifier'


class val RawGirCallback
  """
  A GIR <callback> element. A function-pointer type used for things
  like GObject closures and signal handler signatures declared at
  the GIR level. Same shape as a method, minus the receiver — a
  callback isn't called on an instance.
  """
  let name: String val
  let c_type: String val
  let throws: Bool
  let return_value: RawGirReturnValue val
  let parameters: Array[RawGirParameter val] val

  new val create(
    name': String val,
    c_type': String val,
    throws': Bool,
    return_value': RawGirReturnValue val,
    parameters': Array[RawGirParameter val] val)
  =>
    name = name'
    c_type = c_type'
    throws = throws'
    return_value = return_value'
    parameters = parameters'


class val RawGirAlias
  """
  A GIR <alias> element. Declares a type alias: a name that maps
  to another type's shape. E.g., `<alias name="GType" ...>
  <type name="gsize"/></alias>`. The target type is recorded so
  the validator can resolve aliases when building the GirModel.
  """
  let name: String val
  let c_type: String val
  let target: RawGirType val

  new val create(
    name': String val,
    c_type': String val,
    target': RawGirType val)
  =>
    name = name'
    c_type = c_type'
    target = target'


class val RawGirProperty
  """
  A GIR <property> child of a class or interface. Properties have
  a name (kebab-case in GIR, e.g., "active-window"), a type, and
  access flags. `transfer_ownership` matters for object-typed
  properties (e.g., GtkWindow.child returns a borrowed widget).
  """
  let name: String val
  let typ: RawGirType val
  let readable: Bool
  let writable: Bool
  let construct: Bool
  let construct_only: Bool
  let transfer_ownership: String val

  new val create(
    name': String val,
    typ': RawGirType val,
    readable': Bool,
    writable': Bool,
    construct': Bool,
    construct_only': Bool,
    transfer_ownership': String val)
  =>
    name = name'
    typ = typ'
    readable = readable'
    writable = writable'
    construct = construct'
    construct_only = construct_only'
    transfer_ownership = transfer_ownership'


class val RawGirSignal
  """
  A GIR <glib:signal> child of a class or interface. Same XML
  shape as a method but in the glib namespace and with no
  instance-parameter (signals always receive the emitter as their
  first runtime argument; GIR omits it from <parameters>).
  """
  let name: String val
  let return_value: RawGirReturnValue val
  let parameters: Array[RawGirParameter val] val

  new val create(
    name': String val,
    return_value': RawGirReturnValue val,
    parameters': Array[RawGirParameter val] val)
  =>
    name = name'
    return_value = return_value'
    parameters = parameters'
