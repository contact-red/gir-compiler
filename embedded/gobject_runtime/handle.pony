// GObjectHandle — the universal opaque pointer wrapper.
//
// One instance per live GObject reference. Multiple Pony facades may
// share a single GObjectHandle via ordinary Pony GC; the handle's
// `_final` runs once when no facade holds a reference, releasing the
// underlying GObject ref.

use "lib:glib-2.0"
use "lib:gobject-2.0"

use @g_object_ref[Pointer[U8] tag](obj: Pointer[U8] tag)
use @g_object_unref[None](obj: Pointer[U8] tag)
use @g_object_ref_sink[Pointer[U8] tag](obj: Pointer[U8] tag)


class GObjectHandle
  let _ptr: Pointer[U8] tag

  new adopt(p: Pointer[U8] tag) =>
    """
    Construct from a pointer that already has +1 ref (transfer-full).
    For transfer-none receipts, the caller must call g_object_ref before
    invoking adopt.
    """
    _ptr = p

  new adopt_floating(p: Pointer[U8] tag) =>
    """
    Construct from a pointer that may be a floating reference. Use for
    GInitiallyUnowned descendants whose constructors return floating refs
    (e.g., most GtkWidget subclasses). Sinks the floating ref so we own
    +1 strong reference.
    """
    @g_object_ref_sink(p)
    _ptr = p

  new adopt_borrowed(p: Pointer[U8] tag) =>
    """
    Construct from a borrowed pointer (transfer-none). Adds a +1 ref so
    we own a strong reference independent of the caller's. Use when
    receiving a pointer from a GTK callback (e.g., signal sender).
    """
    @g_object_ref(p)
    _ptr = p

  fun box raw(): Pointer[U8] tag => _ptr

  fun _final() =>
    if not _ptr.is_null() then
      @g_object_unref(_ptr)
    end
