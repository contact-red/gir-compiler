// gir-docs — CLI driver for the GIR-driven Pony documentation generator.
//
// Usage:
//   gir-docs --gir Gtk-4.0,Gio-2.0,GObject-2.0,GLib-2.0 \
//            --target ./gen-docs
//
// Loads one or more GIR namespaces, plans an emit covering every
// type and method in every namespace (no closure analysis), and
// writes the result with translated docstrings attached to each
// generated type and method. The output tree is then ready for
// `pony-doc` consumption.
//
// Sibling of the `gir-compiler` binary; differs only in:
//   - no --src (no user code to scan against)
//   - plans via EverythingPlanner, not ClosurePlanner
//   - the emitter runs with emit_docstrings=true

use "collections"
use "files"
use "../emitter"
use "../gir"
use "../planner"

actor Main
  new create(env: Env) =>
    let parsed = _Args(env)
    if parsed.help_requested then
      _print_usage(env.out)
      return
    end
    if parsed.version_requested then
      env.out.print("gir-docs 0.1.0")
      return
    end
    match parsed.err_msg
    | let msg: String val =>
      env.err.print("gir-docs: " + msg)
      env.err.print("")
      _print_usage(env.err)
      env.exitcode(2)
      return
    end

    let auth = FileAuth(env.root)
    _Pipeline.run(env, auth, parsed)


  fun _print_usage(out: OutStream) =>
    out.print("Usage:")
    out.print("  gir-docs --gir <ns1,ns2,...> --target <dir>")
    out.print("")
    out.print("Options:")
    out.print(
      "  --gir <list>   Comma-separated GIR namespace names")
    out.print(
      "                 (looked up in /usr/share/gir-1.0/)")
    out.print(
      "  --target <dir> Output directory for the doc-ready tree")
    out.print(
      "  --gir-search <dir>")
    out.print(
      "                 Override GIR search root (default")
    out.print(
      "                 /usr/share/gir-1.0)")
    out.print("  -h, --help     Show this help and exit")
    out.print("  --version      Show version and exit")


class val _Args
  let help_requested: Bool
  let version_requested: Bool
  let gir_namespaces: Array[String val] val
  let target_dir: String val
  let gir_search: String val
  let err_msg: (String val | None)

  new val create(env: Env) =>
    var help: Bool = false
    var version: Bool = false
    var girs: Array[String val] iso = recover iso Array[String val] end
    var target: String val = ""
    var search: String val = "/usr/share/gir-1.0"
    var err: (String val | None) = None

    let argv = env.args
    var i: USize = 1
    while i < argv.size() do
      try
        let arg = argv(i)?
        match arg
        | "-h" | "--help" => help = true
        | "--version" => version = true
        | "--gir" =>
          i = i + 1
          let v = argv(i)?
          for ns in v.split(",").values() do girs.push(ns) end
        | "--target" =>
          i = i + 1
          target = argv(i)?
        | "--gir-search" =>
          i = i + 1
          search = argv(i)?
        else
          err = "unrecognised argument: " + arg
        end
      else
        err = "missing value for argument: " + try argv(i - 1)? else "?" end
      end
      i = i + 1
    end

    help_requested = help
    version_requested = version
    gir_namespaces = consume girs
    target_dir = target
    gir_search = search
    err_msg =
      if help_requested or version_requested then
        err
      elseif gir_namespaces.size() == 0 then
        "no --gir namespaces given"
      elseif target_dir.size() == 0 then
        "--target is required"
      else
        err
      end


primitive _Pipeline
  fun run(env: Env, auth: FileAuth, args: _Args val) =>
    // ---- Load + validate the GIR model ----
    let repos = recover iso Array[RawGirRepository val] end
    for ns in args.gir_namespaces.values() do
      let path: String val = args.gir_search + "/" + ns + ".gir"
      env.out.print("loading " + path)
      match GirLoader(auth, path)
      | let r: RawGirRepository val => repos.push(r)
      | let e: GirError =>
        env.err.print("LOAD: " + e.describe())
        env.exitcode(1)
        return
      end
    end
    let model =
      match GirValidator(consume repos)
      | let m: GirModel val => m
      | let e: GirError =>
        env.err.print("VALIDATE: " + e.describe())
        env.exitcode(1)
        return
      end
    env.out.print("loaded " + model.by_qname.size().string()
      + " qnames across " + model.namespaces.size().string()
      + " namespace(s)")

    // ---- Plan everything ----
    let plan = EverythingPlanner(model)
    env.out.print("plan: " + plan.types.size().string()
      + " types, " + plan.method_calls.size().string()
      + " method call(s) for emission")

    // ---- Emit with docstrings ----
    let target = FilePath(auth, args.target_dir)
    match Emitter(plan, model, target, true)
    | let r: EmitOutcome val =>
      env.out.print("emitted " + r.packages_written.string()
        + " package(s), " + r.files_written.string() + " file(s), "
        + r.bytes_written.string() + " bytes")
    | let e: EmitDirError val =>
      env.err.print("EMIT: " + e.describe())
      env.exitcode(1)
    | let e: EmitWriteError val =>
      env.err.print("EMIT: " + e.describe())
      env.exitcode(1)
    end
