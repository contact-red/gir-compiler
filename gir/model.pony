// GirModel — the validated index over one or more loaded GIR
// repositories.
//
// Constructed only by `GirValidator` (which calls the package-private
// `_validated` constructor). Carries the raw repositories as evidence
// and exposes a `resolve(qname)` lookup keyed by GIR's qualified name
// format ("Gtk.Application", "Gio.File", etc.).
//
// v1 scope: minimal validation. The model builds a by-qname index and
// detects duplicate qnames within a namespace. It does NOT yet:
//   - Close transfer-ownership strings to a sealed union
//   - Parse enum/bitfield member values to I64
//   - Resolve type references inline (parent, implements, parameter
//     types stay as raw GIR names; consumers call resolve() at query
//     time)
// These belong in later iterations once a consumer demands them.

use "collections"
use "libxml2"


type NamespaceName is String val


// Tagged wrappers per GIR node kind. Each carries the namespace name
// (which the raw type doesn't know about — RawGirClass is loose
// inside its namespace) plus the raw node. Match-on-kind lets
// consumers dispatch by node category.

class val GirNodeClass
  let namespace: NamespaceName
  let target: RawGirClass val

  new val create(ns: NamespaceName, t: RawGirClass val) =>
    namespace = ns
    target = t


class val GirNodeInterface
  let namespace: NamespaceName
  let target: RawGirInterface val

  new val create(ns: NamespaceName, t: RawGirInterface val) =>
    namespace = ns
    target = t


class val GirNodeRecord
  let namespace: NamespaceName
  let target: RawGirRecord val

  new val create(ns: NamespaceName, t: RawGirRecord val) =>
    namespace = ns
    target = t


class val GirNodeEnumeration
  let namespace: NamespaceName
  let target: RawGirEnumeration val

  new val create(ns: NamespaceName, t: RawGirEnumeration val) =>
    namespace = ns
    target = t


class val GirNodeBitfield
  let namespace: NamespaceName
  let target: RawGirBitfield val

  new val create(ns: NamespaceName, t: RawGirBitfield val) =>
    namespace = ns
    target = t


class val GirNodeCallback
  let namespace: NamespaceName
  let target: RawGirCallback val

  new val create(ns: NamespaceName, t: RawGirCallback val) =>
    namespace = ns
    target = t


class val GirNodeAlias
  let namespace: NamespaceName
  let target: RawGirAlias val

  new val create(ns: NamespaceName, t: RawGirAlias val) =>
    namespace = ns
    target = t


type GirNodeRef is
  ( GirNodeClass
  | GirNodeInterface
  | GirNodeRecord
  | GirNodeEnumeration
  | GirNodeBitfield
  | GirNodeCallback
  | GirNodeAlias )


class val GirModel
  """
  Validated index over loaded GIR repositories.

  `repositories` carries every input repository as evidence (useful for
  iteration, diagnostics, and re-emission tooling). `by_qname` indexes
  every named GIR type from every repository under its qualified name
  ("Gtk.Application", "Gio.File"). `by_c_type` provides reverse lookup
  by the GIR-declared C type name ("GtkApplication", "GFile") — used
  by the doc translator to resolve legacy gtk-doc `#CType` references
  and by the emitter to detect duplicate type declarations across
  namespaces. When two GIR namespaces both declare the same c:type
  (e.g. GIOCondition appears in both GLib and GObject), the first
  one encountered wins the `by_c_type` slot; later declarations are
  detectable as duplicates by comparing their qname against
  by_c_type's stored qname for the same c_type. `namespaces`
  provides per-namespace lookup for "give me everything in Gtk".
  """
  let repositories: Array[RawGirRepository val] val
  let by_qname: Map[String val, GirNodeRef] val
  let by_c_type: Map[String val, GirNodeRef] val
  let namespaces: Map[NamespaceName, RawGirNamespace val] val

  new val _validated(
    repositories': Array[RawGirRepository val] val,
    by_qname': Map[String val, GirNodeRef] val,
    by_c_type': Map[String val, GirNodeRef] val,
    namespaces': Map[NamespaceName, RawGirNamespace val] val)
  =>
    repositories = repositories'
    by_qname = by_qname'
    by_c_type = by_c_type'
    namespaces = namespaces'

  fun box resolve(qname: String): (GirNodeRef | None) =>
    """
    Look up a GIR-qualified type by its full name ("Gtk.Application").
    Returns None for unknown names — including built-in GIR type names
    like "utf8", "gint", "gboolean", which have no qname.
    """
    try by_qname(qname)? else None end

  fun box resolve_by_c_type(c_type: String): (GirNodeRef | None) =>
    """
    Look up a GIR type by its C type name ("GtkApplication", "GFile").
    Used by the doc translator to resolve legacy gtk-doc `#CType`
    references. Returns None when no loaded namespace declares that
    C type — common for types belonging to namespaces the caller
    chose not to load.
    """
    try by_c_type(c_type)? else None end

  fun box namespace_for(name: NamespaceName): (RawGirNamespace val | None) =>
    """
    Look up a namespace by name ("Gtk", "Gio"). Returns None if the
    namespace was not loaded into this model.
    """
    try namespaces(name)? else None end


type GirError is
  ( GirDuplicateQName val
  | GirEmptyModel val
  | GirParseError val
  | GirStructuralError val )


class val GirDuplicateQName
  """
  Two GIR nodes share the same (namespace, local-name) within the
  loaded repositories. This is a fatal validation error — the index
  would be ambiguous.
  """
  let qname: String val
  let kinds: String val      // human-readable description of conflict

  new val create(qname': String val, kinds': String val) =>
    qname = qname'
    kinds = kinds'

  fun box describe(): String iso^ =>
    ("duplicate GIR qname " + qname + ": " + kinds).clone()


class val GirEmptyModel
  """
  No repositories supplied to GirValidator. The model would be empty
  and resolving anything would fail; surface as an explicit error
  rather than silently constructing a useless model.
  """
  new val create() => None

  fun box describe(): String iso^ =>
    "GirValidator received no repositories".clone()


class val GirParseError
  """
  libxml2 refused the GIR file. Wraps the `Xml2Error` so callers can
  inspect domain, level, code, message, file, line — useful for
  diagnostics on malformed XML, encoding issues, missing files, etc.
  """
  let path: String val
  let cause: Xml2Error val

  new val create(path': String val, cause': Xml2Error val) =>
    path = path'
    cause = cause'

  fun box describe(): String iso^ =>
    ("failed to parse GIR " + path + ": " + cause.string()).clone()


class val GirStructuralError
  """
  The GIR file parsed as XML but its shape didn't match what the
  loader expects (missing root, wrong root element, malformed
  nested structure inside <namespace>/<class>/etc.). Internal
  `_load_*` helpers raise; the loader's `apply` boundary catches
  and lifts the failure into this typed variant.
  """
  let path: String val
  let detail: String val

  new val create(path': String val, detail': String val) =>
    path = path'
    detail = detail'

  fun box describe(): String iso^ =>
    ("malformed GIR " + path + ": " + detail).clone()
