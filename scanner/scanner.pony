// SourcePackageScanner — walks one or more user-supplied Pony source
// packages via libponyc at PassParse and produces:
//
//   - referenced_names: every capitalized identifier (TK_ID with
//     uppercase first char) outside declaration positions
//   - used_packages: every `use "X"` string
//   - method_calls: every `<receiver>.<method>(...)` call site where
//     <receiver> resolves to a typed binding whose Pony type maps to
//     a GIR-known qname. Resolution is purely syntactic against a
//     scope-aware binding table built from let/var/embed/fvar/flet/
//     param/lambda-capture declarations with TK_NOMINAL annotations.
//
// User-code discipline (per DESIGN.md): bindings of generated types
// MUST carry a TK_NOMINAL annotation. Unannotated bindings produce
// `ScanErrorUnannotatedBinding`. Receiver expressions that aren't
// simple names (e.g., chained calls `a.b().c()`) are silently dropped
// — DESIGN.md requires intermediate lets for these.

use "collections"
use "files"
use "gir"
use "pony_compiler"


class _ScanContext
  let model: GirModel val
  let scopes: Array[Map[String val, String val] ref] = scopes.create()
  let names: Set[String val] = names.create()
  let pkgs: Set[String val] = pkgs.create()
  let calls: Set[MethodCallRef] = calls.create()
  let errors: Array[ScanError] = errors.create()
  let current_file: String val

  new ref create(model': GirModel val, file': String val) =>
    model = model'
    current_file = file'
    scopes.push(Map[String val, String val])

  fun ref enter_scope() =>
    scopes.push(Map[String val, String val])

  fun ref exit_scope() =>
    try scopes.pop()? end

  fun ref add_binding(name: String val, pony_type: String val) =>
    try scopes(scopes.size() - 1)?(name) = pony_type end

  fun box lookup(name: String): (String val | None) =>
    var i: USize = scopes.size()
    while i > 0 do
      i = i - 1
      try return scopes(i)?(name)? end
    end
    None


primitive SourcePackageScanner
  fun apply(auth: FileAuth,
    packages_in: Array[FilePath] val,
    model: GirModel val)
    : (ScanResult val | ScanError)
  =>
    """
    Scan each FilePath as a Pony source package; return the
    aggregated ScanResult or the first ScanError encountered.
    """
    if packages_in.size() == 0 then
      return ScanEmptyInput
    end

    let names_ref = Set[String val]
    let pkgs_ref = Set[String val]
    let calls_ref = Set[MethodCallRef]
    let stdlib_path = _stdlib_path()

    for pkg_path in packages_in.values() do
      match Compiler.compile(pkg_path, [stdlib_path]
        where limit = PassParse)
      | let program: Program =>
        try
          let user_pkg = program.package() as Package
          for m in user_pkg.modules() do
            let ctx = _ScanContext(model, m.file)
            _walk(m.ast, ctx)
            // Bail on first error within this module.
            for e in ctx.errors.values() do
              return e
            end
            for n in ctx.names.values() do names_ref.set(n) end
            for p in ctx.pkgs.values() do pkgs_ref.set(p) end
            for c in ctx.calls.values() do calls_ref.set(c) end
          end
        end
      | let errs: Array[Error] val =>
        let msgs = recover iso Array[String val] end
        for e in errs.values() do msgs.push(e.msg) end
        return ScanCompileError(pkg_path.path, consume msgs)
      end
    end

    let names_out = recover iso Set[String val] end
    for n in names_ref.values() do names_out.set(n) end
    let pkgs_out = recover iso Set[String val] end
    for p in pkgs_ref.values() do pkgs_out.set(p) end
    let calls_out = recover iso Set[MethodCallRef] end
    for c in calls_ref.values() do calls_out.set(c) end

    ScanResult._validated(
      consume names_out,
      consume pkgs_out,
      consume calls_out)


  fun _walk(node: AST, ctx: _ScanContext) =>
    """
    Depth-first walker with explicit scope push/pop around scope-
    introducing nodes. Handle this node's local payload BEFORE
    recursing so binding declarations are visible to subsequent
    call sites in the same scope.
    """
    let tid = node.id()
    let pushes_scope = _introduces_scope(tid)
    if pushes_scope then ctx.enter_scope() end

    if tid == TokenIds.tk_use() then
      _handle_use(node, ctx)
    elseif _is_binding_node(tid) then
      _handle_binding(node, tid, ctx)
    elseif tid == TokenIds.tk_call() then
      _handle_call(node, ctx)
    elseif tid == TokenIds.tk_id() then
      _handle_id(node, ctx)
    end

    for child in node.children() do
      _walk(child, ctx)
    end

    if pushes_scope then ctx.exit_scope() end


  fun _introduces_scope(tid: TokenId): Bool =>
    (tid == TokenIds.tk_class())
      or (tid == TokenIds.tk_actor())
      or (tid == TokenIds.tk_primitive())
      or (tid == TokenIds.tk_struct())
      or (tid == TokenIds.tk_interface())
      or (tid == TokenIds.tk_trait())
      or (tid == TokenIds.tk_type())
      or (tid == TokenIds.tk_new())
      or (tid == TokenIds.tk_fun())
      or (tid == TokenIds.tk_be())
      or (tid == TokenIds.tk_lambda())
      or (tid == TokenIds.tk_barelambda())
      or (tid == TokenIds.tk_seq())


  fun _is_binding_node(tid: TokenId): Bool =>
    (tid == TokenIds.tk_let())
      or (tid == TokenIds.tk_var())
      or (tid == TokenIds.tk_embed())
      or (tid == TokenIds.tk_fvar())
      or (tid == TokenIds.tk_flet())
      or (tid == TokenIds.tk_param())
      or (tid == TokenIds.tk_lambdacapture())


  fun _handle_use(node: AST, ctx: _ScanContext) =>
    try
      let pkg_node = node(1)?
      if pkg_node.id() == TokenIds.tk_string() then
        match pkg_node.token_value()
        | let s: String val => ctx.pkgs.set(s)
        end
      end
    end


  fun _handle_id(node: AST, ctx: _ScanContext) =>
    match node.token_value()
    | let name: String val =>
      if _is_uppercase_first(name)
        and (not _is_declaration_name(node))
      then
        ctx.names.set(name)
      end
    end


  fun _handle_binding(node: AST, tid: TokenId, ctx: _ScanContext) =>
    """
    Binding declarations: TK_LET / TK_VAR / TK_EMBED / TK_FVAR /
    TK_FLET / TK_PARAM / TK_LAMBDACAPTURE. Structure: child(0) is
    TK_ID with the binding name, child(1) is TK_NOMINAL (annotated)
    or TK_NONE (unannotated).
    """
    try
      let name_node = node(0)?
      let type_node = node(1)?
      if name_node.id() != TokenIds.tk_id() then return end
      let binding_name =
        match name_node.token_value()
        | let s: String val => s
        else return
        end

      if type_node.id() == TokenIds.tk_nominal() then
        // TK_NOMINAL child[1] is the type-name TK_ID
        let ty_id_node = type_node(1)?
        if ty_id_node.id() == TokenIds.tk_id() then
          match ty_id_node.token_value()
          | let pony_ty: String val =>
            ctx.add_binding(binding_name, pony_ty)
          end
        end
      else
        // Annotation missing. Error only for let/var/fvar/flet/embed
        // — param annotations are inferred by ponyc later, and
        // lambdacapture annotations may be elided.
        if (tid == TokenIds.tk_let()) or (tid == TokenIds.tk_var())
          or (tid == TokenIds.tk_fvar()) or (tid == TokenIds.tk_flet())
          or (tid == TokenIds.tk_embed())
        then
          ctx.errors.push(ScanErrorUnannotatedBinding(
            ctx.current_file, node.line(), binding_name))
        end
      end
    end


  fun _handle_call(node: AST, ctx: _ScanContext) =>
    """
    TK_CALL children at PassParse (raw order): [receiver_expr,
    positional_args, named_args, partial_q]. The receiver is
    child(0). If it's a TK_DOT whose left child is a TK_REFERENCE,
    we have a `<name>.<method>(...)` call site and can resolve the
    receiver type via the binding table.
    """
    try
      let receiver = node(0)?
      if receiver.id() != TokenIds.tk_dot() then return end

      let lhs = receiver(0)?
      let method_id_node = receiver(1)?

      if (lhs.id() != TokenIds.tk_reference())
        or (method_id_node.id() != TokenIds.tk_id())
      then
        return
      end

      let receiver_id_node = lhs(0)?
      if receiver_id_node.id() != TokenIds.tk_id() then return end

      let receiver_name =
        match receiver_id_node.token_value()
        | let s: String val => s
        else return
        end
      let method_name =
        match method_id_node.token_value()
        | let s: String val => s
        else return
        end

      match ctx.lookup(receiver_name)
      | let pony_ty: String val =>
        match _resolve_pony_to_qname(pony_ty, ctx.model)
        | let qname: String val =>
          ctx.calls.set(MethodCallRef(qname, method_name))
        end
      end
    end


  fun _resolve_pony_to_qname(pony_name: String, model: GirModel val)
    : (String val | None)
  =>
    """
    Pony type name (e.g. "GtkApplicationWindow") -> GIR qname
    (e.g. "Gtk.ApplicationWindow"). Tries each loaded namespace as
    a prefix; returns the first that resolves in model.by_qname.
    Returns None if no namespace strips off and resolves.
    """
    for ns_name in model.namespaces.keys() do
      if (pony_name.size() > ns_name.size())
        and pony_name.at(ns_name, 0)
      then
        let local: String val =
          pony_name.substring(ns_name.size().isize())
        let qname: String val = ns_name + "." + local
        match model.resolve(qname)
        | let _: GirNodeRef => return qname
        end
      end
    end
    None


  fun _is_uppercase_first(s: String): Bool =>
    if s.size() == 0 then return false end
    try
      let c = s(0)?
      (c >= 'A') and (c <= 'Z')
    else
      false
    end


  fun _is_declaration_name(id_node: AST): Bool =>
    match id_node.parent()
    | let p: AST =>
      let pid = p.id()
      (pid == TokenIds.tk_class())
        or (pid == TokenIds.tk_actor())
        or (pid == TokenIds.tk_struct())
        or (pid == TokenIds.tk_primitive())
        or (pid == TokenIds.tk_trait())
        or (pid == TokenIds.tk_interface())
        or (pid == TokenIds.tk_type())
        or (pid == TokenIds.tk_new())
        or (pid == TokenIds.tk_fun())
        or (pid == TokenIds.tk_be())
        or (pid == TokenIds.tk_use())
    else
      false
    end


  fun _stdlib_path(): String =>
    "/home/red/.local/share/ponyup/"
      + "ponyc-release-0.63.1-x86_64-linux-ubuntu24.04/packages"
