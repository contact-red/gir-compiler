# Change Log

All notable changes to this project will be documented in this file.
This project adheres to [Semantic Versioning](http://semver.org/) and
[Keep a CHANGELOG](http://keepachangelog.com/).

## [unreleased] - unreleased

### Fixed


### Added

- Initial extraction from the contact-red/gtk4 prototype.
- GIR ingest (`gir/`): XML → `RawGirRepository val` → `GirModel val`
  with errors-as-data.
- Source scanner (`scanner/`): scope-aware AST walker producing
  `(type, method)` references via libponyc PassParse.
- Closure planner (`planner/`): method-granular closure ~6 types
  for a hello-world (vs. 207 with the previous type-only closure).
- Emitter (`emitter/`): 7 GIR kinds (class, interface, record,
  enum, bitfield, callback, alias) with 4 v1 method-body shapes.
  Deterministic output (sorted keys throughout).
- CLI binary (`bin/`): `--gir`, `--src`, `--target` flags.
- Embedded runtime: gobject_runtime and gtk_runtime hand-written
  files emitted alongside generated bindings.

### Changed
