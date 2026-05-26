# gir-compiler

A Pony code generator for GObject ecosystem bindings, driven by GIR
(GObject Introspection) XML.

`gir-compiler` reads one or more `.gir` files, scans user Pony source
to discover which types and methods are referenced, computes a
demand-driven closure, and emits a self-contained Pony package tree
that includes both the generated bindings *and* the hand-written
runtime support needed to call into the library at runtime.

## Status

Early. The v1 generator emits classes, interfaces, records, enums,
bitfields, callbacks, and aliases for the GTK4 namespace set
(`Gtk-4.0`, `Gio-2.0`, `GObject-2.0`, `GLib-2.0`). Method emission
covers four body shapes:

  - trivial void methods (primitives in, no return)
  - trivial-return methods (primitives in, primitive out)
  - floating-ref constructors (`new create(...)` adopting via
    `GObjectHandle.adopt_floating`)
  - signal-connect methods (currently only `close-request` wired
    through the embedded runtime)

Anything outside the v1 shape catalog (GError-throwing methods,
object returns, out parameters, varargs, etc.) emits a
`compile_error` skip-stub the user's call site triggers at compile
time with a useful message.

## Usage

```
gir-compiler \
  --gir Gtk-4.0,Gio-2.0,GObject-2.0,GLib-2.0 \
  --src ./my-app \
  --target ./build
```

`--gir` is a comma-separated list of GIR namespace names. They're
looked up in `/usr/share/gir-1.0/` (Linux default).

`--src` is the directory containing your Pony source.

`--target` is the output directory. After running, it contains:

  - `gobject_runtime/` — GObjectHandle and related glue (embedded
    from gir-compiler; written verbatim on each run)
  - `gtk_runtime/` — pinned-actor GtkRuntime, signal trampolines,
    handler type aliases (embedded for the v1 GTK4 slice)
  - `gtk/`, `gio/`, `gobject/`, `glib/` — generated bindings, one
    file per type, organised by GIR namespace

To build the resulting package tree:

```
PONYPATH=./build ponyc my-app -o my-app
```

## Library usage

The pipeline is also importable as four Pony packages:

  - `gir` — GIR XML loader and validator producing `GirModel val`
  - `scanner` — Pony source scanner (typed-binding walker) producing
    `ScanResult val`
  - `planner` — closure planner producing `EmitPlan val`
  - `emitter` — emitter writing the plan + embedded runtime to disk

Useful for tools that want to embed parts of the pipeline (LSP
integration, in-memory analysis, alternative emission backends).

## Build

```
make test
```

Requires `corral` and `ponyc`. The corral fetches `libxml2`,
`pony_compiler` (in-tree under ponyc-work), and `ssl`.

## License

See LICENSE.
