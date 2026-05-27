// Raw GIR types — direct XML structural fidelity, no domain checks.
//
// These types are the output of `GirLoader.apply(auth, path)?`. They
// preserve the GIR file's structure (repository → namespace → class →
// method → parameter) but make no claims about validity: a method
// might reference a type that no namespace declares; a parent might
// be `""`; transfer-ownership might be an unknown value.
//
// The next stage (`GirValidator`) consumes RawGirRepository val and
// produces a validated GirModel val (or a GirValidationError) with
// closed enums, resolved cross-references, and verified invariants.
//
// v1 scope: model just enough of GIR to handle the vertical slice's
// closure (classes, constructors, methods). interfaces, records,
// enumerations, bitfields, signals, properties, callbacks, functions,
// and aliases are deferred until the corresponding emission rules
// land.

class val RawGirRepository
  """
  Top-level GIR document. Contains one or more namespaces. (A single
  GIR file conventionally declares one namespace, but the type allows
  for many.)
  """
  let namespaces: Array[RawGirNamespace val] val

  new val create(namespaces': Array[RawGirNamespace val] val) =>
    namespaces = namespaces'


class val RawGirNamespace
  """
  A GIR <namespace> element. Carries the namespace name (e.g. "Gtk"),
  its version (e.g. "4.0"), and the types declared inside it. `doc`
  carries the verbatim text of the <doc> child if present (empty
  string otherwise) — translated downstream by the `doc_translate`
  package.
  """
  let name: String val
  let version: String val
  let c_identifier_prefixes: String val
  let doc: String val
  let classes: Array[RawGirClass val] val
  let interfaces: Array[RawGirInterface val] val
  let records: Array[RawGirRecord val] val
  let enumerations: Array[RawGirEnumeration val] val
  let bitfields: Array[RawGirBitfield val] val
  let callbacks: Array[RawGirCallback val] val
  let aliases: Array[RawGirAlias val] val
  let functions: Array[RawGirMethod val] val

  new val create(
    name': String val,
    version': String val,
    c_identifier_prefixes': String val,
    doc': String val,
    classes': Array[RawGirClass val] val,
    interfaces': Array[RawGirInterface val] val,
    records': Array[RawGirRecord val] val,
    enumerations': Array[RawGirEnumeration val] val,
    bitfields': Array[RawGirBitfield val] val,
    callbacks': Array[RawGirCallback val] val,
    aliases': Array[RawGirAlias val] val,
    functions': Array[RawGirMethod val] val)
  =>
    name = name'
    version = version'
    c_identifier_prefixes = c_identifier_prefixes'
    doc = doc'
    classes = classes'
    interfaces = interfaces'
    records = records'
    enumerations = enumerations'
    bitfields = bitfields'
    callbacks = callbacks'
    aliases = aliases'
    functions = functions'


class val RawGirClass
  """
  A GIR <class> element. Carries the local class name (e.g.
  "ApplicationWindow"), its C-side type name (e.g.
  "GtkApplicationWindow"), the name of its parent (which may include
  a namespace prefix like "Gio.Application"), the list of interfaces
  it implements, and the constructors, methods, properties, and
  signals declared on the class.
  """
  let name: String val
  let c_type: String val
  let parent: String val           // empty string if no parent
  let doc: String val
  let implements: Array[String val] val
  let constructors: Array[RawGirMethod val] val
  let methods: Array[RawGirMethod val] val
  let properties: Array[RawGirProperty val] val
  let signals: Array[RawGirSignal val] val

  new val create(
    name': String val,
    c_type': String val,
    parent': String val,
    doc': String val,
    implements': Array[String val] val,
    constructors': Array[RawGirMethod val] val,
    methods': Array[RawGirMethod val] val,
    properties': Array[RawGirProperty val] val,
    signals': Array[RawGirSignal val] val)
  =>
    name = name'
    c_type = c_type'
    parent = parent'
    doc = doc'
    implements = implements'
    constructors = constructors'
    methods = methods'
    properties = properties'
    signals = signals'


class val RawGirMethod
  """
  A GIR <constructor>, <method>, or <function> element. (The three
  differ semantically — constructor returns a new instance; method
  takes an instance as first parameter; function is namespace-level
  — but their XML shape is identical.) The element this method came
  from is recorded in `kind`.
  """
  let kind: RawGirMethodKind
  let name: String val
  let c_identifier: String val
  let throws: Bool
  let doc: String val
  let return_value: RawGirReturnValue val
  let parameters: Array[RawGirParameter val] val

  new val create(
    kind': RawGirMethodKind,
    name': String val,
    c_identifier': String val,
    throws': Bool,
    doc': String val,
    return_value': RawGirReturnValue val,
    parameters': Array[RawGirParameter val] val)
  =>
    kind = kind'
    name = name'
    c_identifier = c_identifier'
    throws = throws'
    doc = doc'
    return_value = return_value'
    parameters = parameters'


primitive RawGirMethodKindConstructor
primitive RawGirMethodKindMethod
primitive RawGirMethodKindFunction
type RawGirMethodKind is
  ( RawGirMethodKindConstructor
  | RawGirMethodKindMethod
  | RawGirMethodKindFunction )


class val RawGirReturnValue
  """
  The <return-value> child of a method. Carries the return type and
  ownership-transfer information (raw — `GirValidator` will close it
  to an enum).
  """
  let typ: RawGirType val
  let transfer_ownership: String val
  let nullable: Bool
  let doc: String val

  new val create(
    typ': RawGirType val,
    transfer_ownership': String val,
    nullable': Bool,
    doc': String val)
  =>
    typ = typ'
    transfer_ownership = transfer_ownership'
    nullable = nullable'
    doc = doc'


class val RawGirParameter
  """
  A <parameter> element inside <parameters>. Carries the parameter
  name, its type, ownership-transfer information, the nullable
  annotation, and the verbatim text of any <doc> child.
  """
  let name: String val
  let typ: RawGirType val
  let transfer_ownership: String val
  let nullable: Bool
  let doc: String val

  new val create(
    name': String val,
    typ': RawGirType val,
    transfer_ownership': String val,
    nullable': Bool,
    doc': String val)
  =>
    name = name'
    typ = typ'
    transfer_ownership = transfer_ownership'
    nullable = nullable'
    doc = doc'


class val RawGirType
  """
  A <type> element inside <return-value> or <parameter>. Carries the
  GIR type name (which may be namespace-qualified, e.g.
  "Gio.Application", or a built-in like "utf8" or "guint") and the
  C-side type (e.g. "GtkApplication*"). Empty strings indicate the
  field was absent on the source XML.
  """
  let name: String val
  let c_type: String val

  new val create(name': String val, c_type': String val) =>
    name = name'
    c_type = c_type'
