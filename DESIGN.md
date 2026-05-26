# gtk4 — Pony bindings for the GObject ecosystem

## Status

**Architecture: trait-based bindings emitted on demand from user code.**
Both pillars have empirical support:

- Trait-based emission at 200 stubs (a realistic per-app scale) compiles
  in 2.71s with 337 MB RSS. At 100 stubs, 1.64s. The historical
  35-min/100k-types failure was the result of generating the *entire*
  GIR upfront; demand-driven generation keeps per-app type counts in the
  range where Pony's trait subtyping cost is fine.
- Pony provides `pony_compiler` as a reusable library (the same one
  pony-lsp uses) that exposes libponyc's AST. Generator-time source
  scanning is straightforward.

| Stubs | Trait-based wall (s) | RSS (MB) |
|------:|---------------------:|---------:|
|   100 |                 1.64 |      219 |
|   200 |                 2.71 |      337 |
|   500 |                 6.76 |      964 |
|  1000 |                14.43 |    1,696 |
|  5000 |               103.00 |   10,383 |

(5,000 stubs is the whole-ecosystem worst case if someone *avoided*
demand-driven generation. Practical apps live at the 100–200 end.)

## Goal

A code generator that emits idiomatic Pony bindings for GObject-based C
libraries (GTK, GLib, GIO, GStreamer, libsoup, libadwaita, ...) from
GObject Introspection (GIR) XML. GTK is the first beneficiary; the
design must serve future GObject libraries without per-library special-
casing.

"Idiomatic" means: consumer call sites do not deal with `Pointer[_X]`,
raw `g_object_ref/unref`, or runtime cast macros. The Pony type system
carries type identity via traits; Pony's actor model carries event
dispatch; Pony's reference capabilities carry ownership.

## Non-goals (v1)

- **Cross-version GIR support.** The generator emits for one GIR version
  per build.
- **Generic `g_object_set("name", value)` runtime dispatch.** Property
  setters are typed methods, one per declared property.
- **Reflective introspection at runtime from consumer code.**
  Introspection is a generator-time activity.

Notably *not* a non-goal: subclassing GObject from Pony. With traits,
`class MyButton is GtkButton` is the natural thing to write. v1 can support
this with the runtime GType-registration glue; the type-system shape is
already there.

## Constraints

### Historical

1. **Generating the entire GIR upfront kills the compiler.** A prior
   attempt mirrored all of GTK's type hierarchy as traits; >100,000
   types/interfaces produced a 35-minute compile for a 10-line hello
   world. The fix is *not* to abandon traits — they're idiomatic Pony
   and give clean subtype substitution. The fix is to **generate only
   the types the user actually uses**, plus their GIR-transitive
   parameter/return types.

2. **GObject runtime-cast identity ≠ Pony nominal types.** GTK's C side
   uses cast macros at every call site (`gtk_application_window_new`
   returns `GtkWidget*`, `gtk_application_window_get_id` takes
   `GtkApplicationWindow*`). Resolution: opaque `Pointer[U8] tag` at the
   FFI boundary; Pony nominal type identity carried by traits + concrete
   classes.

3. **Refcaps were never the blocker.** Don't over-engineer around them.

### Pony language

4. **No native varargs in FFI.** `g_object_new(type, "prop", val, NULL)`
   cannot be called directly. Resolution: typed property setters
   generated per property; `g_object_new_with_properties` (non-vararg
   variant) for new-with-properties construction.

5. **No implicit pointer casting.** `Pointer[A]` ≠ `Pointer[B]`. Use
   opaque `Pointer[U8] tag` at the FFI boundary.

6. **No FFI calls in default-impl trait method bodies.** A Pony language
   restriction: trait method bodies with `@some_function()` produce
   "Can't call an FFI function in a default method or behavior."
   Resolution: traits declare abstract method signatures; concrete impl
   classes provide bodies with FFI calls. Inherited methods are
   re-implemented (flattened) on each concrete class. Per-app
   duplication is bounded because demand-driven generation keeps the
   type count small.

7. **Class names cannot contain dots.** `GtkApplicationWindow`, not
   `Gtk.ApplicationWindow`. The dot in source is package-qualified
   access syntax. Generated types use namespace-prefixed names
   (`GtkApplication`, `GioFile`) inside their package.

### Runtime

8. **`pony_send` from a non-scheduler thread is unsafe.** Pony messages
   can only be sent from code running on a Pony scheduler thread. Pinned
   scheduler threads (via `actor_pinning`) count.

9. **GTK's main loop is single-threaded.** All GTK FFI calls must
   originate on the thread running the GTK main loop.

## Architecture

### Generation model: demand-driven at method granularity

The generator does **not** emit bindings for the entire GIR, nor even all
methods of in-closure types. It emits the types the user references plus
the methods, properties, signals, and constructors the user *calls* in
source — with parameter/return types added transitively.

```
1. Generator invokes pony_compiler at PassParse on the user's source dir.
2. Walks the AST, collects:
     - Nominal type references matching binding namespace patterns
       (GtkX, GioX, GstX). Adds to type closure T.
     - Method-name references on those types. Adds to method closure M.
     - Property setter/getter references. Adds to property closure P.
     - Signal connect_X references. Adds to signal closure S.
     - Constructor calls (Gtk.application_window(...)). Adds to C.
3. For each member in M ∪ P ∪ S ∪ C, consults GIR for parameter and
   return types. Adds those types to T (type-only references).
4. Fixed-point iteration until T, M, P, S, C stop growing.
5. For each type t in T, emits a plain Pony class:
     class t                            (no trait split; matches slice shape)
       let _h: GObjectHandle box
       let _runtime: GtkRuntime tag
       new _wrap(h, runtime) => ...     (package-private)
       new create(...) =>               (per GIR <constructor>)
         direct FFI invocation + _adopt or _adopt_floating
       fun box _handle(): GObjectHandle box => _h
       fun ref method_X(...) => ...     (FFI body for each called method)
       fun ref set_prop_Y(...) / fun box prop_Y() => ...   (typed property accessors)
       fun ref connect_signal_Z(...) => ...                (signal connect)
   GIR ancestors not in T are invisible to Pony; their methods the user
   called are flattened onto the descendant class (re-emitted with the
   ancestor's C symbol).
6. For methods that accept "any of several subtypes" (e.g.,
   `GtkWindow.set_child(GtkWidget)`), emits a generated union type for
   the parameter:
     type GtkWidgetSubtypes is (GtkButton | GtkLabel | GtkBox | ...)
     // emitted only when the user actually passes multiple distinct
     // widget types to such a parameter; grows monotonically as user
     // code touches more widgets.
7. ponyc compiles user source + generated bindings normally.
```

Per-stub cost is bounded by what the user *uses*, not what's available.
Numbers (extrapolated from GTK4 GIR; not yet measured):

| App                                            | Types | Stubs (method-gran) | Stubs (type-gran) |
|------------------------------------------------|------:|--------------------:|------------------:|
| Hello-world                                    |     2 |                 ~10 |              ~200 |
| Medium app (20 widgets, casual use)            |   ~30 |                ~150 |            ~3,000 |
| Heavy app (file dialog, list views, drawing)   |   ~80 |                ~700 |           ~10,000 |

14×–30× reduction, scaling favorably with ecosystem size.

### User-code discipline: explicit type annotations on binding-typed locals

To detect "user called `set_title` on a `GtkApplicationWindow`" the
generator needs to know the type of the receiver at PassParse. Pony's
type resolution at PassParse is syntactic — name resolution and full type
checking run at later passes that need the bindings already to exist
(chicken-and-egg).

Resolution: require users to annotate type on let bindings of generated
types:

```pony
let win: GtkApplicationWindow = Gtk.application_window(app)
// rather than: let win = Gtk.application_window(app)
```

This is already idiomatic Pony for clarity. The generator's source scan
treats unannotated bindings of factory-method returns as an error
("can't determine type for emission") rather than silently over-emitting.

### Discoverability: separate `gtk4-doc` tool (deferred to v1.x)

The user explores the API through documentation that's **fully separate
from binding emission**:

- `gtk4-bind` (v1): scans user source + parses GIR + emits `.pony` bindings
  for the closure. Per-project, runs on every source change.
- `gtk4-doc` (v1.x): parses GIR + emits info/man pages for the full
  namespace. Per-system, runs once per GIR version installed.

The two tools share no project state. They share GIR-parsing code via a
common library (`gir_lib`) that handles raw XML → validated `GirModel`.
This decouples the two outputs' lifecycles: GIR updates regenerate docs;
source changes regenerate bindings; neither triggers the other.

v1 ships only `gtk4-bind`. Until `gtk4-doc` exists, users discover the
API through devhelp, docs.gtk.org, or by reading GIR XML directly. None
of these is a great Pony-specific experience, but all three are usable.

### Layered structure

| Layer | Origin | Notes |
|---|---|---|
| `GObjectHandle` | hand-written, ~50 LoC | Universal opaque-pointer wrapper; refcount lifecycle. Non-generic. |
| `GtkRuntime` (pinned actor) | hand-written, ~150 LoC | Owns GLib main loop via `actor_pinning`; serializes all FFI calls. |
| Signal bridge | hand-written, ~150–200 LoC + small C shim | Per-signature C trampolines; closure registry; dispatch into pinned-thread context. |
| Error vocabulary | hand-written + generated | `GtkError` base union; per-domain GError unions generated from GIR. |
| Per-type plain class | generated, 1 per referenced type | Constructors, methods, properties, signal connects. Holds `_h: GObjectHandle box` and `_runtime: GtkRuntime tag`. Methods flattened from GIR ancestors not in closure. No trait split. |
| Subtype union types | generated, when needed | For polymorphic method parameters (`set_child` etc.); union of widget types the user actually passes. Grows monotonically. |
| Generator | hand-written Pony, ~1000–1500 LoC | Uses `pony_compiler` library for AST scanning; reads GIR XML; emits .pony files. (`gtk4-doc` for info/man is a separate v1.x tool.) |

### Per-type emission

For a referenced type `GtkApplicationWindow` — plain class, methods
flattened from non-in-closure ancestors:

```pony
// gtk/GtkApplicationWindow.pony — generated

class GtkApplicationWindow
  let _h: GObjectHandle box
  let _runtime: GtkRuntime tag

  new _wrap(h: GObjectHandle box, runtime: GtkRuntime tag) =>
    _h = h
    _runtime = runtime

  fun box _handle(): GObjectHandle box => _h
  fun box _runtime_ref(): GtkRuntime tag => _runtime

  // Public constructor — direct on the class. User writes
  // `GtkApplicationWindow(app)` and it Just Works.
  new create(app: GtkApplication box) =>
    let raw = @gtk_application_window_new[Pointer[U8] tag](app._handle()._raw())
    _h = GObjectHandle._adopt_floating(raw)
    _runtime = app._runtime_ref()

  // Own methods.
  fun ref set_show_menubar(v: Bool) =>
    @gtk_application_window_set_show_menubar(_h._raw(), v)

  // Flattened from GtkWindow (GtkWindow is not in the closure).
  fun ref set_title(t: String) =>
    @gtk_window_set_title(_h._raw(), t.cstring())

  fun ref present() =>
    @gtk_window_present(_h._raw())

  // Flattened from GtkWidget (also not in closure).
  fun ref show() =>
    @gtk_widget_show(_h._raw())
```

Consumer side:

```pony
let win: GtkApplicationWindow = GtkApplicationWindow(app)
win.set_title("Hello")
win.present()
```

Matches the hand-written vertical slice. No trait, no factory primitive,
no `_<Type>Impl` private class. Direct.

### Polymorphism via generated subtype unions

Pony has no class-inheritance subtyping. For methods that accept "any
subtype of X" (e.g., `set_child(GtkWidget)`), the generator emits a
union type:

```pony
// In gtk/GtkWindow.pony:
class GtkWindow
  // The union grows monotonically as user code passes more widget types.
  fun ref set_child(child: GtkWidgetSubtypes) =>
    let raw = match child
              | let b: GtkButton => b._handle()._raw()
              | let l: GtkLabel => l._handle()._raw()
              // ...
              end
    @gtk_window_set_child(_h._raw(), raw)

// In gtk/_GtkWidgetSubtypes.pony — generated:
type GtkWidgetSubtypes is (GtkButton | GtkLabel)
// Grows as user code passes new widget types to widget-accepting methods.
```

The union is *demand-driven*: only widget types the user actually passes
appear. Adding a new widget at a call site widens the union (monotonic;
old call sites still type-check).

Trade vs. trait subtyping: union-typed parameters require a `match` body
inside the method (one branch per union variant). For a 100-member
union, that's 100 branches. Acceptable at v1 scale (per-app closure
keeps unions small) but a cost to acknowledge.

Subclassing (`class MyButton is GtkButton`) is **not supported in v1**.
Adding it later requires either traits (v1.x: re-architect to trait +
class split) or a separate dispatch mechanism. v1 punts.

### The universal handle (hand-written)

```pony
use @g_object_ref[Pointer[U8] tag](p: Pointer[U8] tag)
use @g_object_unref[None](p: Pointer[U8] tag)
use @g_object_ref_sink[Pointer[U8] tag](p: Pointer[U8] tag)

class GObjectHandle
  let _ptr: Pointer[U8] tag

  new _adopt(p: Pointer[U8] tag) =>
    """Construct from a +1-ref pointer (transfer-full from C)."""
    _ptr = p

  new _adopt_floating(p: Pointer[U8] tag) =>
    """GInitiallyUnowned descendant: sink floating ref."""
    @g_object_ref_sink(p)
    _ptr = p

  fun box _raw(): Pointer[U8] tag => _ptr

  fun _final() =>
    @g_object_unref(_ptr)
```

Non-generic. Multiple concrete classes can share one handle via Pony GC
(each holds a `box` reference); the handle's `_final` runs once when the
last sharer is collected.

### Refcount discipline

- Every `GObjectHandle` holds +1 strong ref; `_final` releases it once.
- Multiple impl classes may share one handle (e.g., when the user holds
  the same widget through two trait views). All views see the same
  underlying C object; no double-ref/double-unref.
- Floating refs are sunk at construction; consumers never see floating
  state.
- `transfer-none` C returns: caller adds a ref before `_adopt`.
- `transfer-full` C returns: `_adopt` directly.
- `transfer-container`: walk container, wrap elements with their
  per-element transfer rule consulted from GIR.

### Pinned `GtkRuntime` actor (hand-written)

```pony
use "actor_pinning"

actor GtkRuntime
  let _env: Env
  let _auth: PinUnpinActorAuth
  var _pinned: Bool = false

  new create(env: Env) =>
    _env = env
    _auth = PinUnpinActorAuth(env.root)
    ActorPinning.request_pin(_auth)
    _wait_for_pin()

  be _wait_for_pin() =>
    if ActorPinning.is_successfully_pinned(_auth) then
      _pinned = true
    else
      _wait_for_pin()
    end

  // Cooperative iteration: each tick polls GLib once, then re-sends.
  // Other behaviors (user closures, signal-dispatch) interleave in the
  // actor mailbox.
  be _iterate() =>
    @g_main_context_iteration[Bool](
      @g_main_context_default[Pointer[U8] tag](), false)
    if _should_continue() then
      _iterate()
    end
  // [...]
```

### Signal handlers: synchronous closure invocation on the pinned thread

**Path A (committed)**: the C trampoline directly invokes the
user-supplied `val` closure synchronously, on the pinned thread, before
returning to GTK. No actor-mailbox hop.

Rationale:
- GTK signals with `gboolean` returns (like `close-request`) require
  the trampoline to return the closure's return value to GTK. Async
  dispatch can't do this.
- The pinned thread *is* a Pony scheduler thread (per `actor_pinning`).
  Pony code can run there directly without round-tripping through a
  mailbox.
- The closure is `val`; the trampoline reads it from the registry
  without consuming, invokes, returns.

Trade: signal handler bodies run synchronously on the pinned thread.
They must be brief — long-running work blocks the GLib main loop.
For work that takes more than a few microseconds, the handler should
send a behavior to a user actor and return immediately.

**user_data integrity** (Stage 2 finding F2 resolution): the
trampoline's `user_data` is NOT a raw Pony pointer. It's a registry
handle:

```
struct {
  uintptr_t   token;      // index into signal registry
  uint32_t    cookie;     // magic value, validated before use
  uint32_t    generation; // bumped on disconnect; prevents reuse-after-free
}
```

The trampoline validates `cookie` and `generation` against the
registry entry before dereferencing. A stale or malicious user_data
fails validation and the trampoline returns the signal's default
value (typically false / 0) instead of dereferencing garbage.

### Consumer vertical slice

```pony
use "gtk"

actor Main
  let _env: Env

  new create(env: Env) =>
    _env = env
    let gtk = GtkRuntime(env)
    gtk.connect_activate("com.example.Hello",
      {(app: GtkApplication ref)(env: Env, me: Main tag) =>
        let win = GtkApplicationWindow(app)
        win.set_title("Hello, Pony")
        win.set_default_size(400, 300)
        win.connect_close_request(
          {(_: GtkApplicationWindow ref)(env: Env, me: Main tag): Bool =>
            env.out.print("goodbye")
            me.shutdown()
            false
          })
        win.present()
      })
    gtk.run()

  be shutdown() => None
```

The generator scans this source, finds `GtkApplication` and
`GtkApplicationWindow` referenced. GIR transitive closure adds nothing
extra. Generator emits 2 plain classes (matching the slice's shape);
`GtkWindow` and `GtkWidget` aren't emitted because the user never
references them as types — their methods called via inheritance
(`set_title`, `present`) are flattened onto `GtkApplicationWindow`.

`GtkApplication` is a special case: it has no public constructor —
it's only created via `gtk.connect_activate(app_id, handler)`, because
construction must happen on the pinned thread and is tied to the GTK
main-loop registration. Other widgets (constructed inside the activate
closure, which already runs on the pinned thread) have direct public
constructors: `GtkApplicationWindow(app)`, `GtkButton.with_label(...)`,
etc.

## Generator implementation

Built in Pony, depends on the `pony_compiler` library
(`/home/red/projects/ponyc-work/ponylang/ponyc/tools/lib/ponylang/pony_compiler/`),
which is the same library `pony-lsp` uses for source analysis.

```
Generator pipeline:
  1. pony_compiler.Compile(user_dir, limit=PassParse) → Program (AST)
  2. Walk AST, collect identifier references whose names match the
     binding namespace prefixes.
  3. Parse GIR XML (library TBD — must ask user before adopting one).
  4. Transitive closure: for each found type, walk GIR methods,
     add parameter/return types.
  5. Emit per-type .pony files into user's gtk/ package directory.
  6. Exit. User runs ponyc separately, or via a wrapper command.
```

The generator binary is a separate executable. Suggested invocation:
`gtk4-bind <user_project>/` writes generated files; `ponyc <user_project>/`
compiles. A `Makefile` or shell wrapper can chain them.

## Scaling story

- **Compile time** is now bounded by what the user actually uses, not
  the total binding surface. Per-app type counts: ~30 (minimal app) to
  ~300 (heavy app using many widget types). Spike data: 200 stubs in
  2.7s; 500 in 6.8s.
- **Adding a new GObject library**: zero impact on existing bindings.
  When the user's code starts referencing types from it, the generator
  emits them.
- **Adding a new widget to an existing library**: when the user
  references it, the next `gtk4-bind` run emits it. Existing emitted
  files unchanged unless the new widget is now used as a parameter/return
  type elsewhere.
- **Cross-library composition**: a shared `gobject_runtime` package
  contains `GObjectHandle`, `GtkRuntime`, the signal trampolines, and
  the user_data registry. Each language-specific binding package
  (`gtk4`, `gio2`, `gst1`) emits generated types into its own package
  but `use "gobject_runtime"` for the shared infrastructure.

### Package boundary: runtime vs generated bindings

`gtk4-bind` writes only to the bindings package (default `gtk4/`).
The runtime lives in a separate package (`gobject_runtime/`) that is
**not** generator-owned — it ships as part of the gtk4-bind
distribution and the user references it via `use "gobject_runtime"`.

This resolves the Stage 2 finding that the hand-written runtime files
in the slice's `gtk/` would be wiped by the generator's atomic
directory swap. The runtime is in a different package; the generator
never touches it.

### Pony reserved-word collisions

GIR has methods named `match`, `type`, `interface`, `ref`, `box`, and
others that collide with Pony keywords. The generator's emission rule:

1. Enumerate Pony's reserved word list at generation time.
2. For any GIR member whose Pony-mapped name collides, emit with a
   trailing underscore: `match` → `match_`, `type` → `type_`.
3. Emit a comment on the renamed method pointing to the original C
   symbol for grep-ability:
   ```pony
   // GIR: gtk_widget_match (renamed: Pony keyword collision)
   fun ref match_(pattern: String): Bool => ...
   ```
4. If the trailing-underscore name still collides (e.g., user has
   `match_` and `match__`), generator errors with
   `RenderError::ReservedWordCollision` listing both. Manual
   resolution via per-method rename map in the generator config.

### GIR auto-load policy

When the transitive closure pulls in a type from a GIR namespace the
user didn't `--load`, the generator auto-loads from a documented path
list (highest precedence first):

1. `--load` paths supplied on the command line (always win)
2. `$XDG_DATA_DIRS/gir-1.0/` (in declared order)
3. `/usr/local/share/gir-1.0/`
4. `/usr/share/gir-1.0/`

The auto-loaded namespace and its path are logged at INFO level to
stderr so the user sees which GIR ended up driving their bindings.

**Non-introspectable type filter**: types with GIR
`introspectable="0"` are excluded from the closure even if a method
signature references them. The generator emits a comment on the
affected method:

```pony
// GIR: gtk_widget_get_event (skipped: parameter type GdkEvent is
// non-introspectable; consult devhelp for the C API)
```

The user can still call the method via raw FFI if needed; the
generated binding just doesn't expose it.

### Cooperative iteration wakeup

The cooperative `g_main_context_iteration(blocking=true)` plus self-
re-send pattern needs a wake mechanism so user-actor → GtkRuntime
behavior sends don't wait for the next GLib event to be processed.

v1 mechanism: an eventfd (Linux) installed as a GLib source. When
GtkRuntime receives a message-from-other-actor behavior, it
internally writes 1 to the eventfd; this wakes the blocked
`g_main_context_iteration` call, which then yields control back to
the actor's mailbox before resuming.

Pseudocode sketch:

```pony
actor GtkRuntime
  let _wakeup_fd: I32        // eventfd
  // ...

  be _iterate() =>
    @g_main_context_iteration(@g_main_context_default(), true)
    if _should_continue() then _iterate() end

  be mutate_widget(...) =>
    // signal wake before doing work, so iterate yields
    @eventfd_write[I32](_wakeup_fd, U64(1))
    // ... do the mutation ...
```

The eventfd's GLib source has empty handler — it exists only to
unblock `g_main_context_iteration`.

macOS/Windows variants use kqueue/IOCP-equivalent primitives or a
g_main_loop_quit + relauch dance. Out of v1 scope (Linux-only); flag
for v1.x.

### Distribution and first-time UX

`gtk4-bind` ships as:
1. A Pony source tree (this project) under `gtk4-bind/`.
2. The `gobject_runtime/` package, similarly.
3. A `corral.json` that depends on `pony_compiler` (Pony's
   AST-tool library).

Users install via `corral fetch`. The compiled binary is invoked as
`gtk4-bind` (or `./gtk4-bind` if the user hasn't put it on `$PATH`).

First-time UX checklist (the "you ran `ponyc` before `gtk4-bind`"
scenario):
- ponyc errors with "package 'gtk4' not found."
- Users should be able to `gtk4-bind --help` to discover the
  command's role.
- README is the primary documentation; explicitly states the
  `gtk4-bind` → `ponyc` ordering.
- A pre-commit hook recipe (Makefile snippet, corral run example) in
  the README so users with mature build flows can wire `gtk4-bind`
  in automatically.

`gtk4-doc` is deferred to v1.x; until then, devhelp / docs.gtk.org
remain the discovery mechanism.

### Test seam specification

Each `_validated`-style boundary type gets a documented test-seam
constructor. These are package-private (`_for_test`) and documented
as "internal use only — bypasses validation."

| Type | Production constructor | Test seam |
|---|---|---|
| `GirModel val` | `GirValidator(raw): (GirModel \| GirError)` | `GirModel._for_test(namespaces, by_qname)` |
| `EmitPlan val` | `ClosurePlanner(gir, scan): (EmitPlan \| PlanError)` | `EmitPlan._for_test(gir, types, methods, ...)` |
| `EmissionBundle val` | `Emitter._render(plan): EmissionBundle val` | (no test seam; produced by `_render` directly in tests) |

`EmitSink` is a trait with two impls: `_FilesystemEmitSink` (production)
and `_InMemoryEmitSink` (tests, plus a `_FaultyEmitSink` decorator for
fault-injection tests).

`Program val` test construction uses `pony_compiler.Compiler.compile_string`
(if available) or falls back to writing temp files. Stub spike work
will verify which path `pony_compiler` supports.

## Open questions (deferred to next implementation iterations)

1. ~~**Signal handler closure cap.**~~ **RESOLVED (2026-05-19)**: val.
   Verified by spike (`spike/closure_cap/`) that `{(I32): I32} val`
   stored in a class field is callable repeatedly, including with
   `Main tag` captures for cross-actor messaging. iso fails the "called
   many times" pattern because each invocation would require destructive
   read. val is the design choice for all signal handlers stored in the
   bridge registry. Captures are restricted to sendable state (`val`
   and `tag`); handlers that need mutable state send messages to actor
   tags rather than capturing references.

2. **`tag → ref` resolution path.** When a user actor sends
   `gtk.with_window(win: GtkWindow tag, work)`, how does GtkRuntime
   resolve the `tag` to a `ref`? Options sketched but not chosen:
   (a) registry inside GtkRuntime keyed by handle pointer; (b) a
   `_wrap_for_pinned` constructor that materializes a fresh `ref`; (c)
   require `box` from consumers.

3. ~~**Threading-token authority pattern.**~~ **DISSOLVED (2026-05-21)**
   by Path α revert. Facade methods are `fun ref`; `ref` doesn't cross
   actor boundaries; widgets are owned by `GtkRuntime`. The compile-time
   enforcement falls out of refcaps + the actor model without a special
   token. Open question reopens if/when v1.x adds traits, since trait
   method receivers can be more permissive than class method receivers.

4. ~~**Cooperative iteration wakeup.**~~ **RESOLVED (2026-05-21)**:
   eventfd-based wake mechanism. `GtkRuntime` holds an eventfd installed
   as a GLib source; every behavior on `GtkRuntime` (other than
   `_iterate` itself) writes 1 to the eventfd before doing work,
   unblocking `g_main_context_iteration(true)` so the actor's mailbox
   can advance. Linux-only for v1; macOS/Windows fallback is v1.x.

5. ~~**GIR parser library.**~~ **RESOLVED (2026-05-20)**: **libxml2 via
   Pony FFI**. Hand-written ~200-line Pony FFI binding for the DOM-walk
   subset we need (open file, walk elements, read attributes/text).
   libxml2 is a transitive dependency of GLib, so already present on
   every machine that runs GTK applications. The pipeline isolates the
   library behind `RawGirRepository` — no XML library types leak
   beyond the GIR loader.

6. **Subclassing GObject from Pony — DEFERRED to v1.x.** Under Path α
   (plain classes, no trait split), `class MyButton is GtkButton`
   does not type-check because Pony classes can't `is` other classes,
   only traits. v1 explicitly does not support custom Pony widgets.
   v1.x will either reintroduce a trait+impl split for the types users
   want to subclass (with the compile-time risk we measured earlier)
   or introduce a separate dispatch mechanism. Decision deferred until
   demand from real Pony GTK apps materializes.

### Emission stage (2026-05-21)

Single mode: render an in-memory bundle, atomically swap it into place.
No flags (no `--check-only`, no `--no-docs`, no `--only-docs`, no
`--force`). No per-file rename. No info/man emission (deferred to
`gtk4-doc`).

```pony
primitive Emitter
  fun apply(plan: EmitPlan val, target: FilePath, sink: EmitSink)
    : (EmissionResult val | EmissionError val)
  =>
    """
    1. _render(plan): EmissionBundle val      (pure; no I/O)
    2. _stage(bundle, target_parent, sink):   (write bundle into
       StagingDir val                          target_parent/staging/)
    3. _swap(staging_dir, target, sink):      (atomic dir rename)
        rename target -> target.old
        rename staging -> target
        rm -rf target.old
    """
```

**`gtk/` is entirely generator-owned.** Users do NOT place hand-written
files in the generated package. Extensions live in user-named packages
(e.g., `my_app_widgets/`). Directory-level rename is then safe — there
is no user content to preserve.

`EmissionBundle val` (boundary type, exposed for `--check-only` futures
and for testing):

```pony
class val EmissionBundle
  let files: Array[FileContent] val      // .pony files only (no docs in v1)
  let manifest: ManifestContent val      // hashes + provenance

  fun types_declared(): Set[String] val  // introspection for tests
  fun types_referenced(): Set[String] val
```

`EmitSink` (capability boundary for I/O — specified):

```pony
trait EmitSink
  fun ref write_file(path: FilePath, content: ByteSeq box)
    : (None | EmissionError val)
  fun ref rename(src: FilePath, dst: FilePath)
    : (None | EmissionError val)
  fun ref delete_recursive(path: FilePath)
    : (None | EmissionError val)
  fun box exists(path: FilePath): Bool
  fun box read_file(path: FilePath)
    : (ByteSeq val | EmissionError val)
  fun box list_dir(path: FilePath)
    : (Array[FilePath] val | EmissionError val)

// Production:    _FilesystemEmitSink     (real filesystem ops)
// Test default:  _InMemoryEmitSink       (in-memory map of path -> content)
// Test fault:    _FaultyEmitSink         (decorator that fails on demand)
```

`EmitPlan` test seam (package-private; documented "internal use only"):

```pony
class val EmitPlan
  new val _validated(...)                     // production path
  new val _for_test(...)                      // test seam; bypasses closure validation
```

Per-file header (no `--check-only`-specific or doc-specific lines):

```pony
// SPDX: generated by gtk4-bind 0.1.0; do not edit by hand.
//
// Source:  GIR Gtk-4.0 (sha256 of GIR file)
// Closure: GtkApplicationWindow [own], GtkWindow [flattened], GtkWidget [flattened]
```

Error vocabulary:

```pony
type EmissionError is
  ( RenderError              // plan referenced something the renderer can't synthesize
  | EmissionLockHeld         // another gtk4-bind running on this project
  | EmissionStagingError     // disk full, permission denied during staging
  | EmissionCommitError      // atomic rename failed (cross-fs? read-only?)
  | EmissionManifestError )  // can't read/write manifest

interface val Stringable
  fun describe(): String iso^
```

Concurrency via `flock(.gtk4-bind/lock, LOCK_EX | LOCK_NB)`. Stale lock
on kernel crash requires manual `rm .gtk4-bind/lock`. Lock-stealing not
in v1.

### Input pipeline (2026-05-20)

Three stages, pure-function primitives, val capabilities throughout:

```
gir paths ─> GirXmlLoader ─> RawGirRepository ─> GirValidator ─> GirModel val
                                                                       │
user source ─> pony_compiler@PassParse ─> Program val                   │
                                              │                         │
                                              ▼                         │
                                  SourceScanner ─> ScanResult val       │
                                                          │             │
                                                          ▼             │
                                          ClosurePlanner(GirModel, ScanResult)
                                                          │
                                                          ▼
                                                   EmitPlan val
                                                          │
                                                          ▼
                                                  Emitter (next stage)
```

Five boundary types: `RawGirRepository` (XML structural fidelity),
`GirModel` (validated; package-private `_validated` constructor),
`Program` (existing, from `pony_compiler`), `ScanResult` (reference
projection), `EmitPlan` (closed emit specification, embeds the
`GirModel` it derives from, carries provenance).

Per-stage typed error unions wrapped in `PipelineError`. Each error
type implements `describe(): String iso^` for self-formatting.

Cross-namespace types pulled in by the transitive closure are
**auto-loaded** from standard GIR paths (`/usr/share/gir-1.0/`,
`/usr/local/share/gir-1.0/`) when the user's `--load` list doesn't cover
them. The generator logs verbose output identifying auto-loaded
namespaces so the dependency is visible in build logs.

Untyped factory-let bindings (`let win = Gtk.application_window(app)`
without `: GtkApplicationWindow`) are scan errors, not warnings —
forces the user to annotate, eliminates the silent-miss failure mode.

No cache in v1. No incremental mode. Full re-emit on every invocation.
Design leaves a clean slot at `GirXmlLoader` for future caching if
measurement justifies it.

## Tension resolutions (closed)

1. **Threading model**: pinned `GtkRuntime` actor with cooperative
   `g_main_context_iteration`. No auto-marshalling. No foreign OS
   threads.
2. **pony-ffi sister project**: not relevant; greenfield.
3. **Subclassing GObject from Pony**: ~~supported~~ Originally landed
   as "type-system shape supports it via traits"; revised 2026-05-21
   to "NOT supported in v1" after Stage 2 revealed Pony's `class is class`
   isn't valid and the trait+impl split adds machinery the user's slice
   doesn't ask for. v1 ships plain classes, no subclassing. See Open Q #6.
4. **Compile-time validation**: spike passed at both flat-graph and
   trait-based scales.
5. **Generator language**: Pony self-hosted, using `pony_compiler`
   library. Ask user before adopting any third-party library (XML parser
   in particular).
6. **`pony_send` from foreign threads**: dissolved by (1).

7. **Path α revert (2026-05-21)**: After Stage 2 evaluation across the
   combined design, reverted to the vertical slice's shape — plain
   classes, no trait+impl split, direct constructors, no `Gtk` factory
   primitive. Subtype unions return for polymorphic method parameters
   (`set_child(GtkWidget)`). Future v1.x can reintroduce trait+impl when
   subclassing is genuinely needed; the cost of doing so later is bounded
   because the generator can re-emit existing types with a different
   shape.

8. **Documentation as separate tool (2026-05-21)**: `gtk4-doc` is a
   v1.x sibling of `gtk4-bind`. Different lifecycle (per GIR, not per
   source change), different output (info/man texinfo), different
   consumer (terminal user). v1 ships only `gtk4-bind`.

9. **Signal trampoline path (2026-05-21)**: Path A committed —
   trampoline invokes the `val` closure synchronously on the pinned
   thread. user_data is a registry handle (token + cookie + generation),
   validated before deref.

10. **Runtime/binding package boundary (2026-05-21)**: hand-written
    runtime lives in `gobject_runtime/` (its own package). Generated
    bindings live in `gtk4/` (or `gio2/`, etc.). Generator only touches
    the bindings package, never the runtime package. Resolves the
    Stage 2 finding that atomic directory swap would wipe the hand-
    written runtime files.
