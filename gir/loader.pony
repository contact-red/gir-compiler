// GIR loader — XML → RawGirRepository val.
//
// Walks a .gir file using libxml2 and builds the raw GIR shape. No
// semantic validation; that's `GirValidator`'s job. Partial: raises
// error on parse failure, missing root, or any structural issue
// that prevents building the raw tree.
//
// v1 scope covers <class>, <interface>, <record>, <enumeration>,
// <bitfield>, <callback>, <alias>, and namespace-level <function>.
// Inside classes/interfaces: <constructor>, <method>, <function>,
// <property>, <glib:signal>, <implements>, <prerequisite>.

use "libxml2"
use "files"


primitive GirNs
  """
  Namespace URI constants for GIR XML. All GIR documents bind these
  to prefixes (the default `""` for core, `c` for the C-API
  namespace, `glib` for GLib-specific elements like signals).
  """
  fun core(): String => "http://www.gtk.org/introspection/core/1.0"
  fun c(): String => "http://www.gtk.org/introspection/c/1.0"
  fun glib(): String => "http://www.gtk.org/introspection/glib/1.0"


primitive GirLoader
  fun apply(auth: FileAuth, path: String)
    : (RawGirRepository val | GirError)
  =>
    """
    Open a .gir file, walk it, and return the raw GIR tree.

    Returns a `GirParseError` if libxml2 refuses the file (the wrapped
    `Xml2Error` carries the file/line/message), or a
    `GirStructuralError` if the file parses as XML but its shape
    doesn't match what we expect (missing root, wrong root element,
    malformed nested element).

    Internal `_load_*` helpers stay partial — their failures carry no
    useful diagnostic data and are caught at this boundary.
    """
    let doc =
      match Xml2Parser.parseFile(auth, path)
      | let d: Xml2Doc => d
      | let err: Xml2Error => return GirParseError(path, err)
      end

    try
      let root = doc.getRootElement()?

      (let root_ns, let root_local) = root.qname()
      if (root_ns != GirNs.core()) or (root_local != "repository") then
        return GirStructuralError(path,
          "root element is not <core:repository>")
      end

      let nss = recover iso Array[RawGirNamespace val] end
      for child in root.getChildren().values() do
        (let cns, let clocal) = child.qname()
        if (cns == GirNs.core()) and (clocal == "namespace") then
          nss.push(_load_namespace(child)?)
        end
      end

      RawGirRepository(consume nss)
    else
      GirStructuralError(path,
        "malformed element inside <namespace>")
    end


  fun _load_namespace(ns_node: Xml2Node): RawGirNamespace val ? =>
    let name = ns_node.getProp("name")
    let version = ns_node.getProp("version")
    let c_prefixes = ns_node.getPropNs(GirNs.c(), "identifier-prefixes")
    let doc = _load_doc(ns_node)

    let classes = recover iso Array[RawGirClass val] end
    let interfaces = recover iso Array[RawGirInterface val] end
    let records = recover iso Array[RawGirRecord val] end
    let enumerations = recover iso Array[RawGirEnumeration val] end
    let bitfields = recover iso Array[RawGirBitfield val] end
    let callbacks = recover iso Array[RawGirCallback val] end
    let aliases = recover iso Array[RawGirAlias val] end
    let functions = recover iso Array[RawGirMethod val] end

    for child in ns_node.getChildren().values() do
      (let cns, let clocal) = child.qname()
      if cns == GirNs.core() then
        match clocal
        | "class" =>
          classes.push(_load_class(child)?)
        | "interface" =>
          interfaces.push(_load_interface(child)?)
        | "record" =>
          records.push(_load_record(child)?)
        | "enumeration" =>
          enumerations.push(_load_enumeration(child))
        | "bitfield" =>
          bitfields.push(_load_bitfield(child))
        | "callback" =>
          callbacks.push(_load_callback(child)?)
        | "alias" =>
          aliases.push(_load_alias(child))
        | "function" =>
          functions.push(_load_method(child, RawGirMethodKindFunction)?)
        end
      end
    end

    RawGirNamespace(
      name, version, c_prefixes, doc,
      consume classes,
      consume interfaces,
      consume records,
      consume enumerations,
      consume bitfields,
      consume callbacks,
      consume aliases,
      consume functions)


  fun _load_class(class_node: Xml2Node): RawGirClass val ? =>
    let name = class_node.getProp("name")
    let c_type = class_node.getPropNs(GirNs.c(), "type")
    let parent = class_node.getProp("parent")
    let doc = _load_doc(class_node)

    let implements = recover iso Array[String val] end
    let constructors = recover iso Array[RawGirMethod val] end
    let methods = recover iso Array[RawGirMethod val] end
    let properties = recover iso Array[RawGirProperty val] end
    let signals = recover iso Array[RawGirSignal val] end

    for child in class_node.getChildren().values() do
      (let cns, let clocal) = child.qname()
      if cns == GirNs.core() then
        match clocal
        | "constructor" =>
          constructors.push(_load_method(child, RawGirMethodKindConstructor)?)
        | "method" =>
          methods.push(_load_method(child, RawGirMethodKindMethod)?)
        | "function" =>
          methods.push(_load_method(child, RawGirMethodKindFunction)?)
        | "property" =>
          properties.push(_load_property(child))
        | "implements" =>
          implements.push(child.getProp("name"))
        end
      elseif (cns == GirNs.glib()) and (clocal == "signal") then
        signals.push(_load_signal(child))
      end
    end

    RawGirClass(
      name, c_type, parent, doc,
      consume implements,
      consume constructors,
      consume methods,
      consume properties,
      consume signals)


  fun _load_interface(iface_node: Xml2Node): RawGirInterface val ? =>
    let name = iface_node.getProp("name")
    let c_type = iface_node.getPropNs(GirNs.c(), "type")
    let doc = _load_doc(iface_node)

    let prerequisites = recover iso Array[String val] end
    let constructors = recover iso Array[RawGirMethod val] end
    let methods = recover iso Array[RawGirMethod val] end
    let properties = recover iso Array[RawGirProperty val] end
    let signals = recover iso Array[RawGirSignal val] end

    for child in iface_node.getChildren().values() do
      (let cns, let clocal) = child.qname()
      if cns == GirNs.core() then
        match clocal
        | "constructor" =>
          constructors.push(_load_method(child, RawGirMethodKindConstructor)?)
        | "method" =>
          methods.push(_load_method(child, RawGirMethodKindMethod)?)
        | "function" =>
          methods.push(_load_method(child, RawGirMethodKindFunction)?)
        | "property" =>
          properties.push(_load_property(child))
        | "prerequisite" =>
          prerequisites.push(child.getProp("name"))
        end
      elseif (cns == GirNs.glib()) and (clocal == "signal") then
        signals.push(_load_signal(child))
      end
    end

    RawGirInterface(
      name, c_type, doc,
      consume prerequisites,
      consume constructors,
      consume methods,
      consume properties,
      consume signals)


  fun _load_record(rec_node: Xml2Node): RawGirRecord val ? =>
    let name = rec_node.getProp("name")
    let c_type = rec_node.getPropNs(GirNs.c(), "type")
    let disguised = rec_node.getProp("disguised") == "1"
    let opaque = rec_node.getProp("opaque") == "1"
    let doc = _load_doc(rec_node)

    let constructors = recover iso Array[RawGirMethod val] end
    let methods = recover iso Array[RawGirMethod val] end

    for child in rec_node.getChildren().values() do
      (let cns, let clocal) = child.qname()
      if cns == GirNs.core() then
        match clocal
        | "constructor" =>
          constructors.push(_load_method(child, RawGirMethodKindConstructor)?)
        | "method" =>
          methods.push(_load_method(child, RawGirMethodKindMethod)?)
        | "function" =>
          methods.push(_load_method(child, RawGirMethodKindFunction)?)
        end
      end
    end

    RawGirRecord(
      name, c_type, disguised, opaque, doc,
      consume constructors,
      consume methods)


  fun _load_enumeration(enum_node: Xml2Node): RawGirEnumeration val =>
    let name = enum_node.getProp("name")
    let c_type = enum_node.getPropNs(GirNs.c(), "type")
    let doc = _load_doc(enum_node)

    let members = recover iso Array[RawGirMember val] end
    for child in enum_node.getChildren().values() do
      (let cns, let clocal) = child.qname()
      if (cns == GirNs.core()) and (clocal == "member") then
        members.push(_load_member(child))
      end
    end

    RawGirEnumeration(name, c_type, doc, consume members)


  fun _load_bitfield(bf_node: Xml2Node): RawGirBitfield val =>
    let name = bf_node.getProp("name")
    let c_type = bf_node.getPropNs(GirNs.c(), "type")
    let doc = _load_doc(bf_node)

    let members = recover iso Array[RawGirMember val] end
    for child in bf_node.getChildren().values() do
      (let cns, let clocal) = child.qname()
      if (cns == GirNs.core()) and (clocal == "member") then
        members.push(_load_member(child))
      end
    end

    RawGirBitfield(name, c_type, doc, consume members)


  fun _load_member(m_node: Xml2Node): RawGirMember val =>
    let name = m_node.getProp("name")
    let value = m_node.getProp("value")
    let c_identifier = m_node.getPropNs(GirNs.c(), "identifier")
    let doc = _load_doc(m_node)
    RawGirMember(name, value, c_identifier, doc)


  fun _load_callback(cb_node: Xml2Node): RawGirCallback val ? =>
    let name = cb_node.getProp("name")
    let c_type = cb_node.getPropNs(GirNs.c(), "type")
    let throws = cb_node.getProp("throws") == "1"
    let doc = _load_doc(cb_node)

    var return_value: (RawGirReturnValue val | None) = None
    let parameters = recover iso Array[RawGirParameter val] end

    for child in cb_node.getChildren().values() do
      (let cns, let clocal) = child.qname()
      if cns == GirNs.core() then
        match clocal
        | "return-value" =>
          return_value = _load_return_value(child)
        | "parameters" =>
          for pchild in child.getChildren().values() do
            (let pns, let plocal) = pchild.qname()
            if (pns == GirNs.core()) and (plocal == "parameter") then
              parameters.push(_load_parameter(pchild))
            end
          end
        end
      end
    end

    let rv = match return_value
             | let v: RawGirReturnValue val => v
             | None => error
             end

    RawGirCallback(name, c_type, throws, doc, rv, consume parameters)


  fun _load_alias(alias_node: Xml2Node): RawGirAlias val =>
    let name = alias_node.getProp("name")
    let c_type = alias_node.getPropNs(GirNs.c(), "type")
    let doc = _load_doc(alias_node)
    let target = _find_first_type(alias_node)
    RawGirAlias(name, c_type, doc, target)


  fun _load_property(prop_node: Xml2Node): RawGirProperty val =>
    let name = prop_node.getProp("name")
    let readable = prop_node.getProp("readable") != "0"  // default "1"
    let writable = prop_node.getProp("writable") == "1"
    let construct' = prop_node.getProp("construct") == "1"
    let construct_only = prop_node.getProp("construct-only") == "1"
    let transfer = prop_node.getProp("transfer-ownership")
    let doc = _load_doc(prop_node)
    let typ = _find_first_type(prop_node)
    RawGirProperty(name, typ, readable, writable, construct',
                   construct_only, transfer, doc)


  fun _load_signal(sig_node: Xml2Node): RawGirSignal val =>
    let name = sig_node.getProp("name")
    let doc = _load_doc(sig_node)

    var return_value: (RawGirReturnValue val | None) = None
    let parameters = recover iso Array[RawGirParameter val] end

    for child in sig_node.getChildren().values() do
      (let cns, let clocal) = child.qname()
      if cns == GirNs.core() then
        match clocal
        | "return-value" =>
          return_value = _load_return_value(child)
        | "parameters" =>
          for pchild in child.getChildren().values() do
            (let pns, let plocal) = pchild.qname()
            if (pns == GirNs.core()) and (plocal == "parameter") then
              parameters.push(_load_parameter(pchild))
            end
          end
        end
      end
    end

    let rv = match return_value
             | let v: RawGirReturnValue val => v
             // Signals without explicit <return-value> are void.
             | None =>
                 RawGirReturnValue(RawGirType("none", "void"), "none", false, "")
             end

    RawGirSignal(name, doc, rv, consume parameters)


  fun _load_method(
    method_node: Xml2Node,
    kind: RawGirMethodKind)
  : RawGirMethod val ?
  =>
    let name = method_node.getProp("name")
    let c_identifier = method_node.getPropNs(GirNs.c(), "identifier")
    let throws = method_node.getProp("throws") == "1"
    let doc = _load_doc(method_node)

    var return_value: (RawGirReturnValue val | None) = None
    let parameters = recover iso Array[RawGirParameter val] end

    for child in method_node.getChildren().values() do
      (let cns, let clocal) = child.qname()
      if cns == GirNs.core() then
        match clocal
        | "return-value" =>
          return_value = _load_return_value(child)
        | "parameters" =>
          for pchild in child.getChildren().values() do
            (let pns, let plocal) = pchild.qname()
            if (pns == GirNs.core()) and (plocal == "parameter") then
              parameters.push(_load_parameter(pchild))
            end
          end
        end
      end
    end

    let rv = match return_value
             | let v: RawGirReturnValue val => v
             | None => error
             end

    RawGirMethod(kind, name, c_identifier, throws, doc, rv, consume parameters)


  fun _load_return_value(rv_node: Xml2Node): RawGirReturnValue val =>
    let transfer = rv_node.getProp("transfer-ownership")
    let nullable = rv_node.getProp("nullable") == "1"
    let doc = _load_doc(rv_node)
    let typ = _find_first_type(rv_node)
    RawGirReturnValue(typ, transfer, nullable, doc)


  fun _load_parameter(param_node: Xml2Node): RawGirParameter val =>
    let name = param_node.getProp("name")
    let transfer = param_node.getProp("transfer-ownership")
    let nullable = param_node.getProp("nullable") == "1"
    let doc = _load_doc(param_node)
    let typ = _find_first_type(param_node)
    RawGirParameter(name, typ, transfer, nullable, doc)


  fun _load_doc(node: Xml2Node): String val =>
    """
    Return the verbatim text content of the <doc> child of `node`, or
    an empty string if `node` has no <doc> child. The text is the
    entity-decoded source from the GIR file (libxml2 handles entity
    decoding when extracting node content); markup translation
    happens later in the `doc_translate` package.
    """
    for child in node.getChildren().values() do
      (let cns, let clocal) = child.qname()
      if (cns == GirNs.core()) and (clocal == "doc") then
        return child.getContent()
      end
    end
    ""


  fun _find_first_type(parent: Xml2Node): RawGirType val =>
    """
    Find the first <type> child of `parent` and wrap it. If the
    parent contains an <array> wrapper instead (GIR's syntax for
    array-typed parameters/returns), record a sentinel
    "array-of-<inner>" so the loader doesn't fail outright. If
    nothing matches, return an "unknown" sentinel. The validator
    will resolve sentinels in a later pass.
    """
    for child in parent.getChildren().values() do
      (let cns, let clocal) = child.qname()
      if cns == GirNs.core() then
        match clocal
        | "type" =>
          let tname = child.getProp("name")
          let tc_type = child.getPropNs(GirNs.c(), "type")
          return RawGirType(tname, tc_type)
        | "array" =>
          let inner = _find_first_type(child)
          return RawGirType("array<" + inner.name + ">", inner.c_type)
        | "varargs" =>
          return RawGirType("varargs", "")
        end
      end
    end
    RawGirType("unknown", "")
