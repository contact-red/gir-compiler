// DocTranslate — translate raw GIR <doc> text to Pony-docstring
// markdown for pony-doc consumption.
//
// Translation set (v1):
//   - HTML entity decode: &amp; &lt; &gt;
//   - Modern gi-docgen refs: [kind@NS.Name] -> markdown link
//   - Legacy gtk-doc refs:
//       #CType                    -> markdown link
//       %TRUE / %FALSE / %NULL    -> `true` / `false` / `None`
//       %CONSTANT                 -> `CONSTANT` (inline-code fallback)
//       @param                    -> `param`
//   - Legacy code blocks: |[ <!-- language="X" --> … ]| -> ```X … ```
//   - Heading demotion: # -> ##, ##->### … (cap at H6)
//
// Anything inside fenced ``` … ``` blocks, legacy |[ … ]| blocks, or
// inline `…` spans is passed through unchanged — refs inside code do
// not get rewritten.
//
// Function-reference forms like `foo_bar()` are intentionally NOT
// translated in v1: the false-positive rate is too high and the text
// renders sensibly as-is.

use "collections"
use "../gir"


primitive UrlBuilder
  """
  pony-doc URL conventions. Type pages are `<package>-<PonyName>.md`
  where the package name is the lowercased namespace and PonyName
  is the actual Pony class name (i.e. the GIR c:type — `GtkWidget`,
  `GApplication`, not `GioApplication`). This matches the file
  pony-doc emits when it compiles the package.

  If pony-doc's filename convention ever changes for a particular
  namespace, this is the only place that needs to be updated.
  """

  fun type_page(namespace: NamespaceName, c_type: String): String val =>
    namespace.lower() + "-" + c_type + ".md"

  fun type_link(namespace: NamespaceName, c_type: String): String val =>
    "[" + c_type + "](" + type_page(namespace, c_type) + ")"

  fun member_link(
    namespace: NamespaceName,
    c_type: String,
    member_name: String)
    : String val
  =>
    """
    Method-anchor URL into the type's page. The member name is
    routed through `PonyIdent.safe_method` so reserved-word
    collisions (`match`, `error`, `ref`, …) get the same `g` prefix
    the emitter applies to the Pony method name itself. Without
    this, the link's anchor wouldn't match the method's actual
    Pony identifier and the cross-reference would dangle.
    """
    let pony_member: String val = PonyIdent.safe_method(member_name)
    "[" + c_type + "." + pony_member + "]("
      + type_page(namespace, c_type) + "#" + pony_member + ")"


primitive DocTranslate
  fun apply(raw: String val, ctx: TranslateContext val): TranslatedDoc val =>
    """
    Translate `raw` GIR <doc> text into a markdown body suitable for
    use as a Pony docstring. The returned `TranslatedDoc` always has
    a usable body — references that fail to resolve fall back to
    inline-code rendering and are reported in `diagnostics`.
    """
    if raw.size() == 0 then
      return TranslatedDoc("", recover val Array[TranslateDiag val] end)
    end
    let scanner = _Scanner(raw, ctx)
    scanner.run()
    let body_pre = scanner.output()
    let body = _DemoteHeadings(body_pre)
    TranslatedDoc(body, scanner.diagnostics_snapshot())


class _Scanner
  """
  Internal state for one translation pass. Walks the input string
  byte-by-byte; for each recognized markup token writes the
  translated form to `_output` and records any diagnostics in
  `_diagnostics`. Unrecognized text is copied verbatim.
  """
  let _input: String val
  let _ctx: TranslateContext val
  embed _output: String ref = String
  embed _diagnostics: Array[TranslateDiag val] = Array[TranslateDiag val]
  var _pos: USize = 0

  new create(input: String val, ctx: TranslateContext val) =>
    _input = input
    _ctx = ctx
    _output.reserve(input.size() + (input.size() / 4))

  fun ref run() =>
    while _pos < _input.size() do
      _step()
    end

  fun box output(): String val =>
    _output.clone()

  fun box diagnostics_snapshot(): Array[TranslateDiag val] val =>
    let size = _diagnostics.size()
    let out = recover iso Array[TranslateDiag val](size) end
    for d in _diagnostics.values() do
      out.push(d)
    end
    consume out

  fun ref _step() =>
    let c: U8 = try _input(_pos)? else return end
    match c
    | '&' => _try_entity()
    | '`' => _handle_backtick()
    | '|' => _try_legacy_code_block()
    | '[' => _try_modern_ref()
    | '#' => _try_type_ref_or_pass()
    | '%' => _try_constant_ref_or_pass()
    | '@' => _try_param_ref_or_pass()
    else
      _output.push(c)
      _pos = _pos + 1
    end

  fun box _at(offset: USize): U8 =>
    try _input(offset)? else U8(0) end

  fun box _starts_with(at: USize, s: String): Bool =>
    if (at + s.size()) > _input.size() then return false end
    var i: USize = 0
    while i < s.size() do
      try
        if _input(at + i)? != s(i)? then return false end
      else
        return false
      end
      i = i + 1
    end
    true

  fun box _at_line_start(): Bool =>
    (_pos == 0) or (_at(_pos - 1) == '\n')

  fun ref _emit_str(s: String box) =>
    _output.append(s)

  // --- entity decode ------------------------------------------------

  fun ref _try_entity() =>
    if _starts_with(_pos, "&amp;") then
      _output.push('&'); _pos = _pos + 5
    elseif _starts_with(_pos, "&lt;") then
      _output.push('<'); _pos = _pos + 4
    elseif _starts_with(_pos, "&gt;") then
      _output.push('>'); _pos = _pos + 4
    else
      _output.push('&'); _pos = _pos + 1
    end

  // --- backticks and fenced code blocks ----------------------------

  fun ref _handle_backtick() =>
    if _starts_with(_pos, "```") then
      _consume_fenced_block()
    else
      _consume_inline_code()
    end

  fun ref _consume_fenced_block() =>
    """
    Copy a ```…``` block verbatim, including the fences. If the
    closing fence is missing, copy the remainder of the input as
    literal text and emit an InvalidMarkup diagnostic.
    """
    let start = _pos
    // emit opening fence
    _output.push('`'); _output.push('`'); _output.push('`')
    _pos = _pos + 3
    // copy until next ```
    while _pos < _input.size() do
      if _starts_with(_pos, "```") then
        _output.push('`'); _output.push('`'); _output.push('`')
        _pos = _pos + 3
        return
      end
      _output.push(_at(_pos))
      _pos = _pos + 1
    end
    _diagnostics.push(InvalidMarkup("unterminated ``` code fence", start))

  fun ref _consume_inline_code() =>
    """
    Copy a `…` inline-code span verbatim, including the delimiters.
    Inline spans in CommonMark may not span newlines; if we hit one,
    emit the backtick as a literal and continue in default mode.
    """
    let start = _pos
    _output.push('`')
    _pos = _pos + 1
    while _pos < _input.size() do
      let c = _at(_pos)
      if c == '`' then
        _output.push('`')
        _pos = _pos + 1
        return
      elseif c == '\n' then
        // Unterminated inline code on this line. CommonMark would
        // render the opening backtick as a literal; do the same.
        return
      end
      _output.push(c)
      _pos = _pos + 1
    end
    _diagnostics.push(InvalidMarkup("unterminated inline code", start))

  // --- legacy gtk-doc code blocks: |[ … ]| -------------------------

  fun ref _try_legacy_code_block() =>
    if not _starts_with(_pos, "|[") then
      _output.push('|'); _pos = _pos + 1
      return
    end
    let start = _pos
    _pos = _pos + 2  // consume "|["
    // Look for optional language annotation: <!-- language="X" -->
    let lang = _extract_language_annotation()
    // Find closing "]|"
    var end_pos: USize = _pos
    var found = false
    while end_pos < _input.size() do
      if _starts_with(end_pos, "]|") then
        found = true
        break
      end
      end_pos = end_pos + 1
    end
    if not found then
      _diagnostics.push(InvalidMarkup("unterminated |[ … ]| block", start))
      // recover: emit "|[" as literal and back off
      _output.push('|'); _output.push('[')
      _pos = start + 2
      return
    end
    // Emit ```lang fence and skip any leading newlines in the source
    // so we don't insert a blank line between the fence and the
    // content.
    _output.append("```")
    _output.append(lang)
    _output.push('\n')
    var content_start = _pos
    while (content_start < end_pos) and (_at(content_start) == '\n') do
      content_start = content_start + 1
    end
    var i = content_start
    while i < end_pos do
      _output.push(_at(i))
      i = i + 1
    end
    // Ensure closing fence is on its own line.
    if (end_pos > content_start) and (_at(end_pos - 1) != '\n') then
      _output.push('\n')
    end
    _output.append("```")
    _pos = end_pos + 2

  fun ref _extract_language_annotation(): String val =>
    """
    If the next non-whitespace token is `<!-- language="X" -->`,
    consume it and return "X". Otherwise advance nothing and return
    an empty string.
    """
    var i = _pos
    while (i < _input.size()) and ((_at(i) == ' ') or (_at(i) == '\n')) do
      i = i + 1
    end
    if not _starts_with(i, "<!-- language=\"") then return "" end
    let lang_start = i + 15  // length of `<!-- language="`
    var j = lang_start
    while (j < _input.size()) and (_at(j) != '"') do
      j = j + 1
    end
    if j >= _input.size() then return "" end
    let lang_end = j
    if not _starts_with(j, "\" -->") then return "" end
    let lang = _input.substring(lang_start.isize(), lang_end.isize())
    _pos = j + 5  // past the closing -->
    consume lang

  // --- modern refs: [kind@NS.Name] ----------------------------------

  fun ref _try_modern_ref() =>
    """
    Recognize `[kind@target]` where kind is one of the known
    gi-docgen role names. If the pattern doesn't match exactly,
    emit `[` as a literal and advance one byte — the surrounding
    text might be a normal markdown link or just bracketed prose.
    """
    let start = _pos
    var i = _pos + 1
    let kind_start = i
    while (i < _input.size()) and _is_lower_alpha(_at(i)) do
      i = i + 1
    end
    if (i == kind_start) or (_at(i) != '@') then
      _output.push('['); _pos = _pos + 1
      return
    end
    let kind = _input.substring(kind_start.isize(), i.isize())
    i = i + 1  // skip @
    let target_start = i
    while (i < _input.size())
      and (_at(i) != ']')
      and (_at(i) != '\n')
    do
      i = i + 1
    end
    if (i >= _input.size()) or (_at(i) != ']') then
      _output.push('['); _pos = _pos + 1
      return
    end
    let target = _input.substring(target_start.isize(), i.isize())
    let end_pos = i + 1
    // `[class@]` with an empty target isn't a real ref — treat as
    // literal text.
    if target.size() == 0 then
      _output.push('['); _pos = _pos + 1
      return
    end
    _emit_modern_ref(consume kind, consume target, start, end_pos)

  fun ref _emit_modern_ref(
    kind: String val,
    target: String val,
    start: USize,
    end_pos: USize)
  =>
    """
    Resolve a recognized modern ref and emit a markdown link, or fall
    back to inline code with a diagnostic if it doesn't resolve.
    """
    match kind
    | "class" | "iface" | "struct" | "enum" | "flags"
    | "error" | "type" | "alias" =>
      _emit_type_ref_qname(target)
    | "method" | "ctor" | "vfunc" | "func" =>
      _emit_method_ref_qname(target, kind == "func")
    | "signal" | "property" =>
      // signal targets are "NS.Class::name"; property are "NS.Class:name"
      _emit_member_ref_qname(target)
    | "const" =>
      _emit_constant_ref_qname(target)
    else
      // Unknown kind — fall back to literal text of the bracket group.
      var i = start
      while i < end_pos do
        _output.push(_at(i))
        i = i + 1
      end
    end
    _pos = end_pos

  fun ref _emit_type_ref_qname(qname: String val) =>
    """
    `qname` is "NS.Name". Resolve against the model; on hit emit a
    link using the resolved node's c:type (so the URL points at the
    file pony-doc actually emits and the label matches the Pony
    class name). On miss emit `qname` as inline code and diagnose.
    """
    match _ctx.model.resolve(qname)
    | let r: GirNodeRef =>
      _emit_str(UrlBuilder.type_link(_node_namespace(r), _node_c_type(r)))
    | None =>
      _diagnostics.push(UnresolvedTypeRef(qname))
      _output.push('`'); _emit_str(qname); _output.push('`')
    end

  fun ref _emit_method_ref_qname(target: String val, is_namespace_func: Bool) =>
    """
    Method/ctor/vfunc target is "NS.Class.member"; func target is
    "NS.name" (a namespace-level function — render as inline code,
    we have no place to link).
    """
    if is_namespace_func then
      // Namespace-level function: no good page to anchor to.
      _output.push('`'); _emit_str(target); _output.push('`')
      return
    end
    // Split off the trailing member.
    try
      let last_dot = target.rfind(".")?
      let owner = target.substring(0, last_dot)
      let member = target.substring(last_dot + 1)
      let owner_str: String val = consume owner
      let member_str: String val = consume member
      match _ctx.model.resolve(owner_str)
      | let r: GirNodeRef =>
        _emit_str(UrlBuilder.member_link(
          _node_namespace(r), _node_c_type(r), member_str))
      | None =>
        _diagnostics.push(UnresolvedMethodRef(target))
        _output.push('`'); _emit_str(target); _output.push('`')
      end
    else
      _diagnostics.push(UnresolvedMethodRef(target))
      _output.push('`'); _emit_str(target); _output.push('`')
    end

  fun ref _emit_member_ref_qname(target: String val) =>
    """
    Signal / property target: "NS.Class::name" or "NS.Class:name".
    We render as a link to the owner page with the member name as
    anchor (pony-doc's signal/property anchor scheme will agree).
    """
    var sep_idx: USize = 0
    var found = false
    var i: USize = 0
    while i < target.size() do
      try
        if target(i)? == ':' then
          sep_idx = i
          found = true
          break
        end
      end
      i = i + 1
    end
    if not found then
      _diagnostics.push(UnresolvedMethodRef(target))
      _output.push('`'); _emit_str(target); _output.push('`')
      return
    end
    let owner = target.substring(0, sep_idx.isize())
    // skip ":" or "::"
    var name_start = sep_idx + 1
    if (name_start < target.size()) then
      try if target(name_start)? == ':' then name_start = name_start + 1 end end
    end
    let member = target.substring(name_start.isize())
    let owner_str: String val = consume owner
    let member_str: String val = consume member
    match _ctx.model.resolve(owner_str)
    | let r: GirNodeRef =>
      _emit_str(UrlBuilder.member_link(
        _node_namespace(r), _node_c_type(r), member_str))
    | None =>
      _diagnostics.push(UnresolvedMethodRef(target))
      _output.push('`'); _emit_str(target); _output.push('`')
    end

  fun ref _emit_constant_ref_qname(target: String val) =>
    """
    Constants are not modeled today, so always fall back to inline
    code. Diagnose so a future pass can pick these up.
    """
    _diagnostics.push(UnresolvedConstantRef(target))
    _output.push('`'); _emit_str(target); _output.push('`')

  fun box _split_qname(qname: String val): (NamespaceName, String val) =>
    """
    "Gtk.Widget" -> ("Gtk", "Widget"). For names without a dot,
    return ("", whole-name) — shouldn't happen for resolved refs.
    """
    try
      let dot = qname.find(".")?
      let ns = qname.substring(0, dot)
      let local = qname.substring(dot + 1)
      (consume ns, consume local)
    else
      ("", qname)
    end

  // --- legacy #CType refs ------------------------------------------

  fun ref _try_type_ref_or_pass() =>
    if _at_line_start() then
      _output.push('#'); _pos = _pos + 1
      return
    end
    let id_start = _pos + 1
    if (id_start >= _input.size()) or not _is_upper_alpha(_at(id_start)) then
      _output.push('#'); _pos = _pos + 1
      return
    end
    var i = id_start
    while (i < _input.size()) and _is_ident_char(_at(i)) do
      i = i + 1
    end
    let c_type = _input.substring(id_start.isize(), i.isize())
    let c_type_str: String val = consume c_type
    match _ctx.model.resolve_by_c_type(c_type_str)
    | let r: GirNodeRef =>
      _emit_str(UrlBuilder.type_link(_node_namespace(r), _node_c_type(r)))
    | None =>
      _diagnostics.push(UnresolvedTypeRef(c_type_str))
      _output.push('`'); _emit_str(c_type_str); _output.push('`')
    end
    _pos = i

  fun box _node_namespace(r: GirNodeRef): NamespaceName =>
    match r
    | let n: GirNodeClass => n.namespace
    | let n: GirNodeInterface => n.namespace
    | let n: GirNodeRecord => n.namespace
    | let n: GirNodeEnumeration => n.namespace
    | let n: GirNodeBitfield => n.namespace
    | let n: GirNodeCallback => n.namespace
    | let n: GirNodeAlias => n.namespace
    end

  fun box _node_local_name(r: GirNodeRef): String val =>
    match r
    | let n: GirNodeClass => n.target.name
    | let n: GirNodeInterface => n.target.name
    | let n: GirNodeRecord => n.target.name
    | let n: GirNodeEnumeration => n.target.name
    | let n: GirNodeBitfield => n.target.name
    | let n: GirNodeCallback => n.target.name
    | let n: GirNodeAlias => n.target.name
    end

  fun box _node_c_type(r: GirNodeRef): String val =>
    """
    Read the GIR c:type off a resolved node. Used for URL building
    so doc cross-refs match what the emitter writes as the Pony
    class name (and what pony-doc uses for the page filename).
    Falls back to the node's local name when c:type is empty —
    defensive only; v1 GIR files always declare c:type.
    """
    let c_type = match r
                 | let n: GirNodeClass => n.target.c_type
                 | let n: GirNodeInterface => n.target.c_type
                 | let n: GirNodeRecord => n.target.c_type
                 | let n: GirNodeEnumeration => n.target.c_type
                 | let n: GirNodeBitfield => n.target.c_type
                 | let n: GirNodeCallback => n.target.c_type
                 | let n: GirNodeAlias => n.target.c_type
                 end
    if c_type.size() > 0 then c_type else _node_local_name(r) end

  // --- legacy %CONSTANT refs ---------------------------------------

  fun ref _try_constant_ref_or_pass() =>
    let id_start = _pos + 1
    if (id_start >= _input.size()) or not _is_upper_alpha_or_us(_at(id_start)) then
      _output.push('%'); _pos = _pos + 1
      return
    end
    var i = id_start
    while (i < _input.size()) and _is_const_char(_at(i)) do
      i = i + 1
    end
    let ident = _input.substring(id_start.isize(), i.isize())
    let ident_str: String val = consume ident
    match ident_str
    | "TRUE" =>
      _output.push('`'); _emit_str("true"); _output.push('`')
    | "FALSE" =>
      _output.push('`'); _emit_str("false"); _output.push('`')
    | "NULL" =>
      _output.push('`'); _emit_str("None"); _output.push('`')
    else
      _output.push('`'); _emit_str(ident_str); _output.push('`')
    end
    _pos = i

  // --- legacy @param refs ------------------------------------------

  fun ref _try_param_ref_or_pass() =>
    let id_start = _pos + 1
    if (id_start >= _input.size()) or not _is_lower_alpha_or_us(_at(id_start)) then
      _output.push('@'); _pos = _pos + 1
      return
    end
    var i = id_start
    while (i < _input.size()) and _is_ident_char(_at(i)) do
      i = i + 1
    end
    let ident = _input.substring(id_start.isize(), i.isize())
    _output.push('`'); _emit_str(consume ident); _output.push('`')
    _pos = i

  // --- character classes -------------------------------------------

  fun box _is_lower_alpha(c: U8): Bool =>
    (c >= 'a') and (c <= 'z')

  fun box _is_upper_alpha(c: U8): Bool =>
    (c >= 'A') and (c <= 'Z')

  fun box _is_upper_alpha_or_us(c: U8): Bool =>
    _is_upper_alpha(c) or (c == '_')

  fun box _is_lower_alpha_or_us(c: U8): Bool =>
    _is_lower_alpha(c) or (c == '_')

  fun box _is_digit(c: U8): Bool =>
    (c >= '0') and (c <= '9')

  fun box _is_ident_char(c: U8): Bool =>
    _is_upper_alpha(c) or _is_lower_alpha(c)
      or _is_digit(c) or (c == '_')

  fun box _is_const_char(c: U8): Bool =>
    _is_upper_alpha(c) or _is_digit(c) or (c == '_')


primitive _DemoteHeadings
  fun apply(s: String val): String val =>
    """
    Demote markdown ATX headings by one level: `# ` -> `## `, … up
    to `##### ` -> `###### `. H6 stays H6 (no overflow). The
    detection rule is strict: at line start, one or more `#` chars
    followed by a space — anything else is left alone, including `#`
    in the middle of a line or `#Foo` without a following space.
    """
    let out = recover iso String(s.size() + 16) end
    var at_line_start = true
    var i: USize = 0
    let n = s.size()
    while i < n do
      try
        let c = s(i)?
        if at_line_start and (c == '#') then
          var j = i
          while (j < n) and (s(j)? == '#') do j = j + 1 end
          let hashes = j - i
          let is_heading = (j < n) and (s(j)? == ' ')
          let new_hashes =
            if is_heading and (hashes < 6) then
              hashes + 1
            else
              hashes
            end
          var k: USize = 0
          while k < new_hashes do
            out.push('#')
            k = k + 1
          end
          i = j
          at_line_start = false
        else
          out.push(c)
          at_line_start = (c == '\n')
          i = i + 1
        end
      else
        i = i + 1
      end
    end
    consume out
