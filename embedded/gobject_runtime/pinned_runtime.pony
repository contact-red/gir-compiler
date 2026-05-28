// PinnedRuntime — the structural interface every generated binding
// stores its runtime reference through.
//
// We can't have every generated class declare `let _runtime:
// GtkRuntime tag` directly, because GtkRuntime lives in the gtk
// package: non-gtk generated packages (gio, gobject, glib …) would
// have to `use "../gtk"`, and the gtk package imports them back,
// closing a cycle. Pony rejects that.
//
// Instead: declare the methods generated bindings need to call on
// their runtime as a structural interface here, in gobject_runtime
// (which no generated package transitively depends on). GtkRuntime
// (in gtk/runtime.pony) declares behaviors with matching signatures
// and Pony's structural matching makes a GtkRuntime tag assignable
// to a PinnedRuntime tag. The cycle never forms because the
// interface itself only references types declared in gobject_runtime.
//
// The methods named here are the minimal set the emitter generates
// calls to today. Adding new signal-connect shapes (beyond
// close-request) is a follow-up: extend this interface and have
// GtkRuntime add the matching behavior.


type CloseRequestHandler is {()} val
  """
  User-supplied closure invoked when a window's "close-request"
  signal fires. Runs after the close has already been allowed (the
  trampoline hard-codes a false return). Use this for cleanup logic.
  """


interface tag PinnedRuntime
  """
  The structural slice of `GtkRuntime` that generated bindings
  invoke. Lives in gobject_runtime to keep this header free of
  references to types declared in dependent packages.
  """
  be register_close_request(
    window_ptr: Pointer[U8] tag,
    handler: CloseRequestHandler)
