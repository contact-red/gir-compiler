// GirValidator — builds a GirModel val from one or more
// RawGirRepository val.
//
// v1 validation: walk every namespace in every repository, emit a
// GirNodeRef wrapper per typed node (class/interface/record/etc.),
// index by "<Namespace>.<LocalName>" qname. Detect duplicate qnames
// within the union of all loaded repositories — that's the one fatal
// error the validator catches today. Returns GirError on failure.
//
// Not yet validated (deferred to later iterations):
//   - Cross-reference resolution (parent, implements, type names in
//     methods stay as raw strings; consumers resolve via the model)
//   - transfer-ownership / enum-value parsing
//   - "introspectable=0" filtering
//   - GIR include resolution (auto-loading dependent namespaces)

use "collections"


primitive GirValidator
  fun apply(repositories: Array[RawGirRepository val] val)
    : (GirModel val | GirError)
  =>
    if repositories.size() == 0 then
      return GirEmptyModel
    end

    let by_qname = recover iso Map[String val, GirNodeRef] end
    let namespaces = recover iso Map[NamespaceName, RawGirNamespace val] end

    for repo in repositories.values() do
      for ns in repo.namespaces.values() do
        let ns_name: NamespaceName = ns.name

        if namespaces.contains(ns_name) then
          return GirDuplicateQName(
            ns_name,
            "namespace declared in multiple repositories")
        end
        namespaces(ns_name) = ns

        for cls in ns.classes.values() do
          let qcls: String val = ns_name + "." + cls.name
          if by_qname.contains(qcls) then
            return GirDuplicateQName(qcls, "conflicts with another node")
          end
          by_qname(qcls) = GirNodeClass(ns_name, cls)
        end

        for iface in ns.interfaces.values() do
          let qif: String val = ns_name + "." + iface.name
          if by_qname.contains(qif) then
            return GirDuplicateQName(qif, "conflicts with another node")
          end
          by_qname(qif) = GirNodeInterface(ns_name, iface)
        end

        for rec in ns.records.values() do
          let qrec: String val = ns_name + "." + rec.name
          if by_qname.contains(qrec) then
            return GirDuplicateQName(qrec, "conflicts with another node")
          end
          by_qname(qrec) = GirNodeRecord(ns_name, rec)
        end

        for enumeration in ns.enumerations.values() do
          let qenum: String val = ns_name + "." + enumeration.name
          if by_qname.contains(qenum) then
            return GirDuplicateQName(qenum, "conflicts with another node")
          end
          by_qname(qenum) = GirNodeEnumeration(ns_name, enumeration)
        end

        for bf in ns.bitfields.values() do
          let qbf: String val = ns_name + "." + bf.name
          if by_qname.contains(qbf) then
            return GirDuplicateQName(qbf, "conflicts with another node")
          end
          by_qname(qbf) = GirNodeBitfield(ns_name, bf)
        end

        for cb in ns.callbacks.values() do
          let qcb: String val = ns_name + "." + cb.name
          if by_qname.contains(qcb) then
            return GirDuplicateQName(qcb, "conflicts with another node")
          end
          by_qname(qcb) = GirNodeCallback(ns_name, cb)
        end

        for al in ns.aliases.values() do
          let qal: String val = ns_name + "." + al.name
          if by_qname.contains(qal) then
            return GirDuplicateQName(qal, "conflicts with another node")
          end
          by_qname(qal) = GirNodeAlias(ns_name, al)
        end
      end
    end

    GirModel._validated(
      repositories,
      consume by_qname,
      consume namespaces)
