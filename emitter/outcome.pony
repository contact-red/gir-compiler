// EmitOutcome — summary of a successful emission. Returned by
// Emitter.apply on the success path so the caller can report what
// happened without re-walking the plan or the filesystem.

class val EmitOutcome
  let packages_written: USize
  let files_written: USize
  let bytes_written: USize

  new val _validated(
    packages_written': USize,
    files_written': USize,
    bytes_written': USize)
  =>
    packages_written = packages_written'
    files_written = files_written'
    bytes_written = bytes_written'


type EmitError is
  ( EmitDirError val
  | EmitWriteError val )


class val EmitDirError
  let path: String val
  let detail: String val

  new val create(path': String val, detail': String val) =>
    path = path'
    detail = detail'

  fun box describe(): String iso^ =>
    ("emitter directory error at " + path + ": " + detail).clone()


class val EmitWriteError
  let path: String val
  let detail: String val

  new val create(path': String val, detail': String val) =>
    path = path'
    detail = detail'

  fun box describe(): String iso^ =>
    ("emitter file-write error at " + path + ": " + detail).clone()
