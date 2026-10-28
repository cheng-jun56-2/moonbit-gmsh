///| Tokenization never skips across a binary payload boundary. Header line endings

///|
/// are consumed exactly once; a binary tag may legitimately begin with 0x0A.
priv struct Cursor {
  data : Bytes
  mut p : Int
  mut binary : Bool
  mut little : Bool
  mut width : Int
}

///|
fn Cursor::need(c : Cursor, n : Int) -> Unit raise MeshError {
  if n < 0 || n > c.data.length() - c.p {
    bad("truncated MSH at byte \{c.p}")
  }
}

///|
fn Cursor::line(c : Cursor) -> String raise {
  let start = c.p
  while c.p < c.data.length() && c.data[c.p] != 10 {
    c.p = c.p + 1
    if c.p - start > 1048576 {
      bad("text line exceeds 1 MiB")
    }
  }
  let end = if c.p > start && c.data[c.p - 1] == 13 { c.p - 1 } else { c.p }
  if c.p < c.data.length() {
    c.p = c.p + 1
  }
  @utf8.decode(c.data[start:end], ignore_bom=false)
}

///|
fn white(b : Byte) -> Bool {
  b == 32 || b == 9 || b == 10 || b == 13
}

///|
fn Cursor::word(c : Cursor) -> String raise {
  while c.p < c.data.length() && white(c.data[c.p]) {
    c.p = c.p + 1
  }
  let start = c.p
  while c.p < c.data.length() && !white(c.data[c.p]) {
    c.p = c.p + 1
    if c.p - start > 128 {
      bad("numeric token too long")
    }
  }
  if start == c.p {
    bad("expected token at end of input")
  }
  @utf8.decode(c.data[start:c.p])
}

///|
fn decimal(s : String) -> Int raise {
  if s.is_empty() {
    bad("empty integer")
  }
  let mut digits = 0
  for i, ch in s.iter().to_array() {
    if ch >= '0' && ch <= '9' {
      digits = digits + 1
    } else if i != 0 || (ch != '-' && ch != '+') {
      bad("invalid decimal integer: \{s}")
    }
  }
  if digits == 0 {
    bad("invalid integer")
  }
  @string.parse_int(s)
}

///|
fn Cursor::ai(c : Cursor) -> Int raise {
  decimal(c.word())
}

///|
fn Cursor::ar(c : Cursor) -> Double raise {
  let s = c.word()
  if !s
    .iter()
    .all(ch => {
      (ch >= '0' && ch <= '9') ||
      ch == '+' ||
      ch == '-' ||
      ch == '.' ||
      ch == 'e' ||
      ch == 'E'
    }) {
    bad("invalid real token")
  }
  let x = @string.parse_double(s)
  if !finite(x) {
    bad("nonfinite real value")
  }
  x
}

///|
fn Cursor::eol(c : Cursor) -> Unit raise {
  // Only horizontal whitespace is permitted before the one required line ending.
  while c.p < c.data.length() && (c.data[c.p] == 32 || c.data[c.p] == 9) {
    c.p = c.p + 1
  }
  if c.p < c.data.length() && c.data[c.p] == 13 {
    c.p = c.p + 1
  }
  c.need(1)
  if c.data[c.p] != 10 {
    bad("expected line ending at byte \{c.p}")
  }
  c.p = c.p + 1
}

///|
fn Cursor::bits(c : Cursor, n : Int) -> UInt64 raise {
  c.need(n)
  let mut value = 0UL
  for i = 0; i < n; i = i + 1 {
    let at = if c.little { c.p + n - 1 - i } else { c.p + i }
    value = (value << 8) | c.data[at].to_uint64()
  }
  c.p = c.p + n
  value
}

///|
fn Cursor::integer(c : Cursor) -> Int raise {
  if c.binary {
    c.bits(4).to_uint().reinterpret_as_int()
  } else {
    c.ai()
  }
}

///|
fn Cursor::size(c : Cursor) -> Int raise {
  if !c.binary {
    c.ai()
  } else {
    let n = c.bits(c.width)
    if n > 2147483647UL {
      bad("64-bit tag/count exceeds portable signed-32-bit limit")
    }
    n.to_int()
  }
}

///|
fn Cursor::real(c : Cursor) -> Double raise {
  if !c.binary {
    c.ar()
  } else {
    let x = c.bits(8).reinterpret_as_double()
    if !finite(x) {
      bad("nonfinite binary value")
    }
    x
  }
}

///|
fn count(n : Int, limit : Int) -> Int raise {
  if n < 0 || n > limit {
    bad("negative or excessive section count: \{n}")
  }
  n
}

///|
fn Cursor::end_section(
  c : Cursor,
  name : String,
  binary_payload : Bool,
) -> Unit raise {
  if binary_payload {
    c.eol()
  }
  let marker = c.word()
  if marker != "$End\{name}" {
    bad("expected $End\{name}, got \{marker}")
  }
  if c.p < c.data.length() {
    c.eol()
  }
}

///|
fn Cursor::quoted(c : Cursor) -> String raise {
  while c.p < c.data.length() && white(c.data[c.p]) {
    c.p = c.p + 1
  }
  c.need(1)
  if c.data[c.p] != 34 {
    bad("expected quoted string")
  }
  c.p = c.p + 1
  let start = c.p
  while c.p < c.data.length() && c.data[c.p] != 34 {
    // A valid UTF-8 string uses at most three bytes per UTF-16 code unit.
    // The model limits field strings in code units, not encoded bytes.
    if c.p - start >= 12288 ||
      c.data[c.p] == 10 ||
      c.data[c.p] == 13 ||
      c.data[c.p] == 92 {
      bad("unsupported quoted string or escape")
    }
    c.p = c.p + 1
  }
  c.need(1)
  let value = @utf8.decode(c.data[start:c.p])
  if value.length() > 4096 {
    bad("quoted string exceeds 4096 UTF-16 code units")
  }
  c.p = c.p + 1
  value
}

///| Reject unknown binary sections: searching for an ASCII delimiter inside binary

///|
/// data is unsafe. Unknown ASCII section bodies are preserved as opaque text.
pub fn decode(data : Bytes) -> Mesh raise {
  if data.length() > 134217728 {
    bad("MSH file exceeds 128 MiB")
  }
  let c : Cursor = { data, p: 0, binary: false, little: true, width: 8, }
  if c.line() != "$MeshFormat" {
    bad("MSH must start with $MeshFormat")
  }
  let version = c.word()
  let ft = c.ai()
  let width = c.ai()
  c.eol()
  if (version != "2.2" && version != "4.1") ||
    (ft != 0 && ft != 1) ||
    (width != 8 && !(version == "4.1" && width == 4)) {
    bad("supported formats: MSH 2.2/4.1, ASCII/binary, size_t 4/8")
  }
  c.width = width
  c.binary = ft == 1
  if c.binary {
    let magic = c.bits(4)
    if magic == 16777216UL {
      c.little = false
    } else if magic != 1UL {
      bad("invalid endian sentinel")
    }
  }
  c.end_section("MeshFormat", c.binary)
  let ns : Array[Node] = []
  let es : Array[Element] = []
  let ents : Array[Entity] = []
  let names : Array[PhysicalName] = []
  let fields : Array[Field] = []
  let unknown : Array[Section] = []
  let seen : Map[String, Bool] = Map([])
  while c.p < data.length() {
    let line = c.line().trim().to_owned()
    if line.is_empty() {
      continue
    }
    if !line.has_prefix("$") || line.has_prefix("$End") {
      bad("expected section marker")
    }
    let name = line[1:].to_owned()
    if name == "MeshFormat" {
      bad("duplicate MeshFormat")
    }
    if ["Nodes", "Elements", "Entities", "PhysicalNames"].contains(name) {
      if seen.contains(name) {
        bad("duplicate core section: \{name}")
      }
      seen[name] = true
    }
    match name {
      "PhysicalNames" => {
        let n = count(c.ai(), 1000000)
        for _ in 0..<n {
          let dim = c.ai()
          let tag = c.ai()
          let text = c.quoted()
          names.push({ dim, tag, name: text, })
        }
        c.end_section(name, false)
      }
      "Entities" => {
        if version != "4.1" {
          bad("Entities requires 4.1")
        }
        let counts = [c.size(), c.size(), c.size(), c.size()]
        for dim = 0; dim < 4; dim = dim + 1 {
          let n = count(counts[dim], 1000000 - ents.length())
          for _ in 0..<n {
            let tag = c.integer()
            let bounds = []
            for _ in 0..<(if dim == 0 { 3 } else { 6 }) {
              bounds.push(c.real())
            }
            let np = count(c.size(), 1000000)
            let physical = []
            for _ in 0..<np {
              physical.push(c.integer())
            }
            let nb = if dim == 0 { 0 } else { count(c.size(), 1000000) }
            let boundary = []
            for _ in 0..<nb {
              boundary.push(c.integer())
            }
            ents.push({ dim, tag, bounds, physical, boundary, })
          }
        }
        c.end_section(name, c.binary)
      }
      "Nodes" =>
        if version == "2.2" {
          let n = count(c.ai(), 1000000)
          c.eol()
          for _ in 0..<n {
            let tag = c.integer()
            ns.push({
              tag,
              xyz: [c.real(), c.real(), c.real()],
              dim: -1,
              entity: 0,
              parameters: [],
            })
          }
          c.end_section(name, c.binary && n > 0)
        } else {
          let blocks = count(c.size(), 1000000)
          let total = count(c.size(), 1000000)
          let lo = c.size()
          let hi = c.size()
          for _ in 0..<blocks {
            let dim = c.integer()
            let entity = c.integer()
            let param = c.integer()
            if dim < 0 || dim > 3 || (param != 0 && param != 1) {
              bad("invalid node block dimension/parametric flag")
            }
            let n = count(c.size(), total - ns.length())
            let tags = []
            for _ in 0..<n {
              tags.push(c.size())
            }
            for tag in tags {
              let xyz = [c.real(), c.real(), c.real()]
              let parameters = []
              if param == 1 {
                for _ in 0..<dim {
                  parameters.push(c.real())
                }
              }
              ns.push({ tag, xyz, dim, entity, parameters, })
            }
          }
          check_range(ns.map(n => n.tag), total, lo, hi)
          c.end_section(name, c.binary)
        }
      "Elements" =>
        if version == "2.2" {
          let total = count(c.ai(), 1000000)
          c.eol()
          while es.length() < total {
            let first = c.integer()
            let kind = if c.binary { first } else { c.integer() }
            let n = if c.binary {
              count(c.integer(), total - es.length())
            } else {
              1
            }
            if n == 0 {
              bad("empty legacy binary element block")
            }
            let nt = count(c.integer(), 1024)
            let (_, width) = element_shape(kind)
            for _ in 0..<n {
              let tag = if c.binary { c.integer() } else { first }
              let tags = []
              for _ in 0..<nt {
                tags.push(c.integer())
              }
              if tags.any(x => x == -2147483648) {
                bad("legacy tag out of range")
              }
              let nodes = []
              for _ in 0..<width {
                nodes.push(c.integer())
              }
              let physical = if nt > 0 && tags[0] != 0 { [tags[0]] } else { [] }
              let entity = if nt > 1 { tags[1] } else { 0 }
              let extra = if nt > 2 { tags[2:].to_owned() } else { [] }
              es.push({ tag, kind, nodes, entity, physical, extra, })
            }
          }
          c.end_section(name, c.binary && total > 0)
        } else {
          let blocks = count(c.size(), 1000000)
          let total = count(c.size(), 1000000)
          let lo = c.size()
          let hi = c.size()
          for _ in 0..<blocks {
            let dim = c.integer()
            let entity = c.integer()
            let kind = c.integer()
            let (expected, width) = element_shape(kind)
            if dim != expected {
              bad("element block dimension disagrees with type")
            }
            let n = count(c.size(), total - es.length())
            for _ in 0..<n {
              let tag = c.size()
              let nodes = []
              for _ in 0..<width {
                nodes.push(c.size())
              }
              es.push({ tag, kind, nodes, entity, physical: [], extra: [], })
            }
          }
          check_range(es.map(e => e.tag), total, lo, hi)
          c.end_section(name, c.binary)
        }
      "NodeData" | "ElementData" => {
        if fields.length() >= 1024 {
          bad("too many field frames")
        }
        let n = count(c.ai(), 1024)
        let strings = []
        for _ in 0..<n {
          strings.push(c.quoted())
        }
        let n = count(c.ai(), 1024)
        let reals = []
        for _ in 0..<n {
          reals.push(c.ar())
        }
        let n = count(c.ai(), 1024)
        let integers = []
        for _ in 0..<n {
          integers.push(c.ai())
        }
        c.eol()
        if integers.length() < 3 || ![1, 3, 9].contains(integers[1]) {
          bad("invalid field integer header")
        }
        let n = count(integers[2], 1000000)
        let entries = []
        for _ in 0..<n {
          let tag = c.integer()
          let values = []
          for _ in 0..<integers[1] {
            values.push(c.real())
          }
          entries.push({ tag, values, })
        }
        fields.push({ location: name, strings, reals, integers, entries, })
        c.end_section(name, c.binary && n > 0)
      }
      _ => {
        if c.binary {
          bad("cannot safely preserve unknown binary section: \{name}")
        }
        if unknown.length() >= 1024 {
          bad("too many unknown sections")
        }
        let body = StringBuilder()
        let mut ended = false
        while c.p < data.length() {
          let s = c.line()
          if s == "$End\{name}" {
            ended = true
            break
          }
          body.write_string(s)
          body.write_string("\n")
        }
        if !ended {
          bad("unterminated unknown section")
        }
        unknown.push({ name, body: body.to_string(), })
      }
    }
  }
  if !seen.contains("Nodes") || !seen.contains("Elements") {
    bad("Nodes and Elements sections required")
  }
  if version == "4.1" {
    let groups : Map[String, Array[Int]] = Map([])
    for e in ents {
      groups["\{e.dim}:\{e.tag}"] = e.physical
    }
    for i, e in es {
      let (dim, _) = element_shape(e.kind)
      es[i] = { ..e, physical: groups.get("\{dim}:\{e.entity}").unwrap_or([]), }
    }
    // 4.1 permits files without Entities. Synthesize classification bounds with no
    // physical claims, only when the entire Entities section is absent.
    if !seen.contains("Entities") {
      synthesize_entities(ns, es, ents)
    }
  }
  mesh(ns, es, entities=ents, names~, fields~, unknown~, version~)
}

///|
fn check_range(
  tags : Array[Int],
  total : Int,
  lo : Int,
  hi : Int,
) -> Unit raise {
  if tags.length() != total {
    bad("section count mismatch")
  }
  let mut min = 2147483647
  let mut max = 0
  for tag in tags {
    if tag < min {
      min = tag
    }
    if tag > max {
      max = tag
    }
  }
  if total == 0 {
    if lo != 0 || hi != 0 {
      bad("empty range must be 0 0")
    }
  } else if lo != min || hi != max {
    bad("section min/max tag mismatch")
  }
}

///|
fn synthesize_entities(
  ns : Array[Node],
  es : Array[Element],
  out : Array[Entity],
) -> Unit raise {
  let groups : Map[String, (Int, Int, Array[Int], Array[Double])] = Map([])
  let index : Map[Int, Node] = Map([])
  for n in ns {
    index[n.tag] = n
  }
  for n in ns {
    if n.dim >= 0 && n.entity > 0 {
      let key = "\{n.dim}:\{n.entity}"
      let bounds = match groups.get(key) {
        Some((_, _, _, b)) => b
        None => {
          let b = [n.xyz[0], n.xyz[1], n.xyz[2], n.xyz[0], n.xyz[1], n.xyz[2]]
          groups[key] = (n.dim, n.entity, [], b)
          b
        }
      }
      grow(bounds, n.xyz)
    }
  }
  for e in es {
    let (dim, _) = element_shape(e.kind)
    if e.entity <= 0 {
      bad("entity synthesis requires positive entity tags")
    }
    let key = "\{dim}:\{e.entity}"
    let first = match index.get(e.nodes[0]) {
      Some(n) => n
      None => {
        bad("missing node during entity synthesis")
        { tag: 1, xyz: [0.0, 0.0, 0.0], dim: -1, entity: 0, parameters: [], }
      }
    }
    let bounds = match groups.get(key) {
      Some((_, _, phys, b)) => {
        if phys != e.physical && !phys.is_empty() {
          bad("same entity has inconsistent physical groups")
        }
        groups[key] = (dim, e.entity, e.physical, b)
        b
      }
      None => {
        let b = [
          first.xyz[0],
          first.xyz[1],
          first.xyz[2],
          first.xyz[0],
          first.xyz[1],
          first.xyz[2],
        ]
        groups[key] = (dim, e.entity, e.physical, b)
        b
      }
    }
    for tag in e.nodes {
      match index.get(tag) {
        Some(n) => grow(bounds, n.xyz)
        None => bad("missing node")
      }
    }
  }
  let keys = groups.keys().to_array()
  keys.sort()
  for key in keys {
    let (dim, tag, physical, b) = groups[key]
    out.push({
      dim,
      tag,
      physical,
      bounds: if dim == 0 {
        b[:3].to_owned()
      } else {
        b
      },
      boundary: [],
    })
  }
}

///|
fn grow(b : Array[Double], xyz : Array[Double]) -> Unit {
  for j = 0; j < 3; j = j + 1 {
    if xyz[j] < b[j] {
      b[j] = xyz[j]
    }
    if xyz[j] > b[j + 3] {
      b[j + 3] = xyz[j]
    }
  }
}
