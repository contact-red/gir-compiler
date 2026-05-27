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
    let by_c_type = recover iso Map[String val, GirNodeRef] end
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
          let node = GirNodeClass(ns_name, cls)
          by_qname(qcls) = node
          if cls.c_type.size() > 0 then by_c_type(cls.c_type) = node end
        end

        for iface in ns.interfaces.values() do
          let qif: String val = ns_name + "." + iface.name
          if by_qname.contains(qif) then
            return GirDuplicateQName(qif, "conflicts with another node")
          end
          let node = GirNodeInterface(ns_name, iface)
          by_qname(qif) = node
          if iface.c_type.size() > 0 then by_c_type(iface.c_type) = node end
        end

        for rec in ns.records.values() do
          let qrec: String val = ns_name + "." + rec.name
          if by_qname.contains(qrec) then
            return GirDuplicateQName(qrec, "conflicts with another node")
          end
          let node = GirNodeRecord(ns_name, rec)
          by_qname(qrec) = node
          if rec.c_type.size() > 0 then by_c_type(rec.c_type) = node end
        end

        for enumeration in ns.enumerations.values() do
          let qenum: String val = ns_name + "." + enumeration.name
          if by_qname.contains(qenum) then
            return GirDuplicateQName(qenum, "conflicts with another node")
          end
          let node = GirNodeEnumeration(ns_name, enumeration)
          by_qname(qenum) = node
          if enumeration.c_type.size() > 0 then
            by_c_type(enumeration.c_type) = node
          end
        end

        for bf in ns.bitfields.values() do
          let qbf: String val = ns_name + "." + bf.name
          if by_qname.contains(qbf) then
            return GirDuplicateQName(qbf, "conflicts with another node")
          end
          let node = GirNodeBitfield(ns_name, bf)
          by_qname(qbf) = node
          if bf.c_type.size() > 0 then by_c_type(bf.c_type) = node end
        end

        for cb in ns.callbacks.values() do
          let qcb: String val = ns_name + "." + cb.name
          if by_qname.contains(qcb) then
            return GirDuplicateQName(qcb, "conflicts with another node")
          end
          let node = GirNodeCallback(ns_name, cb)
          by_qname(qcb) = node
          if cb.c_type.size() > 0 then by_c_type(cb.c_type) = node end
        end

        for al in ns.aliases.values() do
          let qal: String val = ns_name + "." + al.name
          if by_qname.contains(qal) then
            return GirDuplicateQName(qal, "conflicts with another node")
          end
          let node = GirNodeAlias(ns_name, al)
          by_qname(qal) = node
          if al.c_type.size() > 0 then by_c_type(al.c_type) = node end
        end
      end
    end

    GirModel._validated(
      repositories,
      consume by_qname,
      consume by_c_type,
      consume namespaces)
