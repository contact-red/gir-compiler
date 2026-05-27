// gir-compiler — CLI driver for the GIR-driven Pony binding generator.
//
// Usage:
//   gir-compiler --gir Gtk-4.0,Gio-2.0,GObject-2.0,GLib-2.0 \
//                --src ./my-app \
//                --target ./build
//
// Reads one or more GIR namespaces from /usr/share/gir-1.0/, scans
// the user Pony source for type and method references, computes the
// demand-driven closure, and writes the result (embedded runtime +
// generated bindings) to the target directory.

use "collections"
use "files"
use "../emitter"
use "../gir"
use "../planner"
use "../scanner"

actor Main
  new create(env: Env) =>
    let parsed = _Args(env)
    if parsed.help_requested then
      _print_usage(env.out)
      return
    end
    if parsed.version_requested then
      env.out.print("gir-compiler 0.1.0")
      return
    end
    match parsed.err_msg
    | let msg: String val =>
      env.err.print("gir-compiler: " + msg)
      env.err.print("")
      _print_usage(env.err)
      env.exitcode(2)
      return
    end

    let auth = FileAuth(env.root)
    _Pipeline.run(env, auth, parsed)


  fun _print_usage(out: OutStream) =>
    out.print(
      "Usage:")
    out.print(
      "  gir-compiler --gir <ns1,ns2,...> --src <dir> --target <dir>")
    out.print("")
    out.print("Options:")
    out.print(
      "  --gir <list>   Comma-separated GIR namespace names")
    out.print(
      "                 (looked up in /usr/share/gir-1.0/)")
    out.print(
      "  --src <dir>    Directory containing Pony source to scan")
    out.print(
      "  --target <dir> Output directory for generated bindings")
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
  let src_dir: String val
  let target_dir: String val
  let gir_search: String val
  let err_msg: (String val | None)

  new val create(env: Env) =>
    var help: Bool = false
    var version: Bool = false
    var girs: Array[String val] iso = recover iso Array[String val] end
    var src: String val = ""
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
        | "--src" =>
          i = i + 1
          src = argv(i)?
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
    src_dir = src
    target_dir = target
    gir_search = search
    err_msg =
      if help_requested or version_requested then
        err
      elseif gir_namespaces.size() == 0 then
        "no --gir namespaces given"
      elseif src_dir.size() == 0 then
        "--src is required"
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

    // ---- Scan user source ----
    let src_path = FilePath(auth, args.src_dir)
    let packages = recover val [as FilePath: src_path] end
    let scan =
      match SourcePackageScanner(auth, packages, model)
      | let r: ScanResult val => r
      | let e: ScanCompileError val =>
        env.err.print("SCAN: " + e.describe())
        env.exitcode(1)
        return
      | let e: ScanErrorUnannotatedBinding val =>
        env.err.print("SCAN: " + e.describe())
        env.exitcode(1)
        return
      | let _: ScanEmptyInput val =>
        env.err.print("SCAN: empty input")
        env.exitcode(1)
        return
      end
    env.out.print("scanned " + scan.referenced_names.size().string()
      + " referenced names, " + scan.method_calls.size().string()
      + " method calls")

    // ---- Plan closure ----
    let plan = ClosurePlanner(model, scan)
    env.out.print("plan: " + plan.types.size().string()
      + " types, " + plan.method_calls.size().string()
      + " method calls, converged in " + plan.iterations.string()
      + " iteration(s)")

    // ---- Emit ----
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
