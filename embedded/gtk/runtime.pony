"""
GtkRuntime — the pinned actor that owns the GLib main loop and serves
as the single FFI execution context for the binding.

All GTK FFI calls originate from behaviors on this actor. Signal
trampolines (bare functions registered with C) dispatch back into Pony
by sending behaviors to this actor; since the actor is pinned and
trampolines fire on the pinned thread, the message send is from a Pony
scheduler thread (safe).

Cooperative main-loop iteration: each `_iterate` behavior runs one
`g_main_context_iteration` call (blocking until an event arrives or
the iteration completes), then re-sends itself. Other behaviors
(signal-dispatch, widget mutations from other actors) interleave with
iterations as the mailbox processes.
"""

use "actor_pinning"
use "collections"
use "../gobject_runtime"
use "lib:gobject-2.0"
use "lib:gio-2.0"
use "lib:glib-2.0"

use @gtk_application_new[Pointer[U8] tag](
  application_id: Pointer[U8] tag,
  flags: U32)
use @g_application_register[Bool](
  application: Pointer[U8] tag,
  cancellable: Pointer[U8] tag,
  err: Pointer[Pointer[U8]] tag)
use @g_application_activate[None](application: Pointer[U8] tag)
use @g_application_quit[None](application: Pointer[U8] tag)
use @g_main_context_default[Pointer[U8] tag]()
use @g_main_context_iteration[Bool](
  context: Pointer[U8] tag,
  may_block: Bool)
use @g_signal_connect_data[U64](
  instance: Pointer[U8] tag,
  detailed_signal: Pointer[U8] tag,
  c_handler: Pointer[None] tag,
  data: GtkRuntime tag,
  destroy_data: Pointer[None] tag,
  connect_flags: U32)


type ActivateHandler is {(GtkApplication ref)} val
  """
  User-supplied closure invoked when the application's "activate"
  signal fires. Runs synchronously inside a GtkRuntime behavior.
  """

type CloseRequestHandler is {()} val
  """
  User-supplied closure invoked when a window's "close-request" signal
  fires. Runs after the close has already been allowed (the trampoline
  hard-codes a false return). Use this for cleanup logic.
  """


// Bare-function trampolines. C ABI. Called by GTK on the pinned thread.
// The user_data parameter is typed as `GtkRuntime tag` directly; Pony's
// runtime preserves the actor reference across the C round-trip.
primitive _Trampolines
  fun @on_activate(
    sender: Pointer[U8] tag,
    runtime: GtkRuntime tag)
  =>
    runtime._dispatch_activate(sender)

  fun @on_close_request(
    sender: Pointer[U8] tag,
    runtime: GtkRuntime tag)
  : I32
  =>
    // Always return 0 (FALSE) → allow the close to proceed. The handler
    // runs async; sync-prevent-close requires a different signal-bridge
    // shape and is out of v1 scope.
    runtime._dispatch_close_request(sender)
    I32(0)


actor GtkRuntime
  let _env: Env
  let _auth: PinUnpinActorAuth
  var _pinned: Bool = false

  // Registries keyed by sender pointer (USize for Map key compatibility).
  // One map per signal kind.
  let _activate_handlers: Map[USize, ActivateHandler] =
    _activate_handlers.create()
  let _close_request_handlers: Map[USize, CloseRequestHandler] =
    _close_request_handlers.create()

  var _app: Pointer[U8] tag = Pointer[U8]
  var _running: Bool = false

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

  be connect_activate(app_id: String, handler: ActivateHandler) =>
    if not _pinned then
      // Defer until we're pinned.
      connect_activate(app_id, handler)
      return
    end
    let raw = @gtk_application_new(app_id.cstring(), U32(0))
    if raw.is_null() then
      _env.err.print("gtk_application_new failed")
      return
    end
    _app = raw
    _activate_handlers(raw.usize()) = handler
    @g_signal_connect_data(
      raw,
      "activate".cstring(),
      addressof _Trampolines.on_activate,
      this,
      Pointer[None],
      U32(0))

  be run() =>
    if not _pinned then
      run()
      return
    end
    if _app.is_null() then
      _env.err.print("run() called before connect_activate")
      return
    end
    let registered = @g_application_register(
      _app, Pointer[U8], Pointer[Pointer[U8]])
    if not registered then
      _env.err.print("g_application_register failed")
      return
    end
    _running = true
    @g_application_activate(_app)
    _iterate()

  be _iterate() =>
    if not _running then return end
    // Blocking iteration: waits until an event arrives, processes one
    // event, returns. During the call, signal trampolines may fire on
    // this same thread and queue _dispatch_* behaviors that will run
    // when this _iterate returns and the mailbox processes the next
    // behavior.
    @g_main_context_iteration(@g_main_context_default(), true)
    _iterate()

  be _dispatch_activate(sender: Pointer[U8] tag) =>
    try
      let handler = _activate_handlers(sender.usize())?
      let app = GtkApplication._wrap(
        GObjectHandle.adopt_borrowed(sender),
        this)
      handler(app)
    end

  be _register_close_request(
    window_ptr: Pointer[U8] tag,
    handler: CloseRequestHandler)
  =>
    _close_request_handlers(window_ptr.usize()) = handler
    @g_signal_connect_data(
      window_ptr,
      "close-request".cstring(),
      addressof _Trampolines.on_close_request,
      this,
      Pointer[None],
      U32(0))

  be _dispatch_close_request(sender: Pointer[U8] tag) =>
    try
      let handler = _close_request_handlers(sender.usize())?
      handler()
    end

  be quit() =>
    _running = false
    if not _app.is_null() then
      @g_application_quit(_app)
    end
