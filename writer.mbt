///|
priv struct Writer {
  out : Array[Byte]
  binary : Bool
  little : Bool
  width : Int
}

///|
fn Writer::text(w : Writer, s : String) -> Unit raise {
  let b = @utf8.encode(s)
  if b.length() > 134217728 - w.out.length() {
    bad("output exceeds 128 MiB")
  }
  for x in b {
    w.out.push(x)
  }
}

///|
fn Writer::bits(w : Writer, v : UInt64, n : Int) -> Unit raise {
  if n > 134217728 - w.out.length() {
    bad("output exceeds 128 MiB")
  }
  for i in 0..<n {
    let shift = (if w.little { i } else { n - 1 - i }) * 8
    w.out.push((v >> shift).to_byte())
  }
}

///|
fn Writer::integer(w : Writer, v : Int) -> Unit raise {
  if w.binary {
    w.bits(v.reinterpret_as_uint().to_uint64(), 4)
  } else {
    w.text("\{v} ")
  }
}

///|
fn Writer::size(w : Writer, v : Int) -> Unit raise {
  if v < 0 {
    bad("negative size/tag")
  }
  if w.binary {
    w.bits(v.to_uint64(), w.width)
  } else {
    w.text("\{v} ")
  }
}

///|
fn Writer::real(w : Writer, v : Double) -> Unit raise {
  if w.binary {
    w.bits(v.reinterpret_as_uint64(), 8)
  } else {
    w.text("\{v} ")
  }
}

///|
fn Writer::row(w : Writer) -> Unit raise {
  if !w.binary {
    w.text("\n")
  }
}

///|
fn Writer::end(w : Writer, name : String, payload : Bool) -> Unit raise {
  if w.binary && payload {
    w.text("\n")
  }
  w.text("$End\{name}\n")
}

///|
fn tag_range(tags : Array[Int]) -> (Int, Int) {
  let mut lo = 2147483647
  let mut hi = 0
  for t in tags {
    if t < lo {
      lo = t
    }
    if t > hi {
      hi = t
    }
  }
  (if tags.is_empty() { 0 } else { lo }, hi)
}

///|
/// Allocate among unused positive IDs, including the valid signed32 maximum.
/// At most the bounded model's entities can be occupied; never require max+1
/// merely because an existing semantic elementary tag happens to be maximal.
fn inferred_entity_tag(
  next : Array[Int],
  occupied : Map[String, Bool],
  dim : Int,
) -> Int {
  let mut tag = next[dim]
  while occupied.contains("\{dim}:\{tag}") {
    tag = if tag == 2147483647 { 1 } else { tag + 1 }
  }
  occupied["\{dim}:\{tag}"] = true
  next[dim] = if tag == 2147483647 { 1 } else { tag + 1 }
  tag
}

///| Canonical classification for legacy files: preserve positive elementary

///| tags; allocate tags for unclassified elements by dimension+physical set.

///| Assign each node to its highest-dimensional incident entity; isolated nodes

///|
/// get point entities. This is inferred mesh classification, not CAD recovery.
fn Mesh::classified(self : Mesh) -> Mesh raise {
  if !self.ents.is_empty() {
    return self
  }
  let es = self.elements()
  let ns = self.nodes()
  let highest = [0, 0, 0, 0]
  let occupied : Map[String, Bool] = Map([])
  for e in es {
    let (d, _) = element_shape(e.kind)
    if e.entity > 0 {
      occupied["\{d}:\{e.entity}"] = true
      highest[d] = highest[d].max(e.entity)
    }
  }
  let next = highest.map(t => if t == 2147483647 { 1 } else { t + 1 })
  let allocated : Map[String, Int] = Map([])
  let groups : Map[String, Array[Int]] = Map([])
  let classification : Map[Int, (Int, Int)] = Map([])
  for i, e in es {
    let (dim, _) = element_shape(e.kind)
    let entity = if e.entity > 0 {
      e.entity
    } else {
      let key = "\{dim}:" + id_key(e.physical)
      match allocated.get(key) {
        Some(t) => t
        None => {
          let t = inferred_entity_tag(next, occupied, dim)
          allocated[key] = t
          t
        }
      }
    }
    let key = "\{dim}:\{entity}"
    match groups.get(key) {
      Some(p) =>
        if p != e.physical {
          bad("legacy entity has inconsistent physical groups")
        }
      None => groups[key] = e.physical
    }
    es[i] = { ..e, entity, }
    for tag in e.nodes {
      match classification.get(tag) {
        Some((d, _)) => if dim > d { classification[tag] = (dim, entity) }
        None => classification[tag] = (dim, entity)
      }
    }
  }
  for i, n in ns {
    let (dim, entity) = match classification.get(n.tag) {
      Some(pair) => pair
      None => {
        let t = inferred_entity_tag(next, occupied, 0)
        (0, t)
      }
    }
    ns[i] = { ..n, dim, entity, }
  }
  let ents = []
  synthesize_entities(ns, es, ents)
  mesh(
    ns,
    es,
    entities=ents,
    names=self.names,
    fields=self.fs,
    unknown=self.unknown,
    version=self.version,
  )
}

///| Loss is opt-in: 4.1 entity BRep/classification and parametric coordinates have

///| no 2.2 equivalent; multiple physical groups collapse to the first only when

///| allow_loss=true. Unknown text requires explicit without_unknown() to change

///|
/// version or emit binary. Legacy extra tags similarly require permission for 4.1.
pub fn Mesh::encode(
  self : Mesh,
  version? : String = self.version,
  binary? : Bool = false,
  little? : Bool = true,
  size_width? : Int = 8,
  allow_loss? : Bool = false,
) -> Bytes raise {
  if version != "2.2" && version != "4.1" {
    bad("write version must be 2.2 or 4.1")
  }
  if size_width != 8 && !(version == "4.1" && size_width == 4) {
    bad("invalid size_t width")
  }
  if !self.unknown.is_empty() && (version != self.version || binary) {
    bad("drop unknown sections explicitly before version/binary conversion")
  }
  if !allow_loss {
    if version == "2.2" &&
      (
        !self.ents.is_empty() ||
        self.ns.any(n => !n.parameters.is_empty()) ||
        self.es.any(e => e.physical.length() > 1)
      ) {
      bad(
        "2.2 would lose entity/parametric/multiple-group metadata; require allow_loss",
      )
    }
    if version == "4.1" && self.es.any(e => !e.extra.is_empty()) {
      bad("4.1 would lose legacy partition/extra tags; require allow_loss")
    }
  }
  let m = if version == "4.1" { self.classified() } else { self }
  let w : Writer = { out: [], binary, little, width: size_width, }
  w.text("$MeshFormat\n\{version} \{if binary {1} else {0}} \{size_width}\n")
  if binary {
    w.bits(1UL, 4)
  }
  w.end("MeshFormat", binary)
  if !m.names.is_empty() {
    w.text("$PhysicalNames\n\{m.names.length()}\n")
    for p in m.names {
      w.text("\{p.dim} \{p.tag} \"\{p.name}\"\n")
    }
    w.end("PhysicalNames", false)
  }
  if version == "4.1" {
    w.text("$Entities\n")
    for d in 0..<4 {
      w.size(m.ents.filter(e => e.dim == d).length())
    }
    w.row()
    for d in 0..<4 {
      for e in m.ents {
        if e.dim != d {
          continue
        }
        w.integer(e.tag)
        for x in e.bounds {
          w.real(x)
        }
        w.size(e.physical.length())
        for p in e.physical {
          w.integer(p)
        }
        if d > 0 {
          w.size(e.boundary.length())
          for b in e.boundary {
            w.integer(b)
          }
        }
        w.row()
      }
    }
    w.end("Entities", true)
  }
  w.text("$Nodes\n")
  if version == "2.2" {
    w.text("\{m.ns.length()}\n")
    for n in m.ns {
      w.integer(n.tag)
      for x in n.xyz {
        w.real(x)
      }
      w.row()
    }
    w.end("Nodes", !m.ns.is_empty())
  } else {
    let groups : Map[String, Array[Node]] = Map([])
    let order = []
    for n in m.ns {
      let key = "\{n.dim}:\{n.entity}:\{!n.parameters.is_empty()}"
      match groups.get(key) {
        Some(a) => a.push(n)
        None => {
          groups[key] = [n]
          order.push(key)
        }
      }
    }
    let (lo, hi) = tag_range(m.ns.map(n => n.tag))
    w.size(order.length())
    w.size(m.ns.length())
    w.size(lo)
    w.size(hi)
    w.row()
    for key in order {
      let a = groups[key]
      let n = a[0]
      w.integer(n.dim)
      w.integer(n.entity)
      w.integer(if n.parameters.is_empty() { 0 } else { 1 })
      w.size(a.length())
      w.row()
      for n in a {
        w.size(n.tag)
        w.row()
      }
      for n in a {
        for x in n.xyz {
          w.real(x)
        }
        for x in n.parameters {
          w.real(x)
        }
        w.row()
      }
    }
    w.end("Nodes", true)
  }
  w.text("$Elements\n")
  if version == "2.2" {
    w.text("\{m.es.length()}\n")
    // Single-element binary blocks keep arbitrary legacy tags exactly, including
    // heterogeneous partition metadata. Readers must not assume one block/type.
    for e in m.es {
      let nt = 2 + e.extra.length()
      if binary {
        w.integer(e.kind)
        w.integer(1)
        w.integer(nt)
        w.integer(e.tag)
      } else {
        w.integer(e.tag)
        w.integer(e.kind)
        w.integer(nt)
      }
      w.integer(if e.physical.is_empty() { 0 } else { e.physical[0] })
      w.integer(e.entity)
      for t in e.extra {
        w.integer(t)
      }
      for t in e.nodes {
        w.integer(t)
      }
      w.row()
    }
    w.end("Elements", !m.es.is_empty())
  } else {
    // MSH permits repeated entity/type blocks. Keep contiguous runs so file
    // order preserves Mesh::subset's requested element order across entities.
    let groups : Array[Array[Element]] = []
    for e in m.es {
      if !groups.is_empty() {
        let last = groups[groups.length() - 1]
        if last[0].kind == e.kind && last[0].entity == e.entity {
          last.push(e)
          continue
        }
      }
      groups.push([e])
    }
    let (lo, hi) = tag_range(m.es.map(e => e.tag))
    w.size(groups.length())
    w.size(m.es.length())
    w.size(lo)
    w.size(hi)
    w.row()
    for a in groups {
      let e = a[0]
      let (dim, _) = element_shape(e.kind)
      w.integer(dim)
      w.integer(e.entity)
      w.integer(e.kind)
      w.size(a.length())
      w.row()
      for e in a {
        w.size(e.tag)
        for n in e.nodes {
          w.size(n)
        }
        w.row()
      }
    }
    w.end("Elements", true)
  }
  for f in m.fs {
    w.text("$\{f.location}\n\{f.strings.length()}\n")
    for s in f.strings {
      w.text("\"\{s}\"\n")
    }
    w.text("\{f.reals.length()}\n")
    for x in f.reals {
      w.text("\{x}\n")
    }
    w.text("\{f.integers.length()}\n")
    for x in f.integers {
      w.text("\{x}\n")
    }
    for d in f.entries {
      w.integer(d.tag)
      for x in d.values {
        w.real(x)
      }
      w.row()
    }
    w.end(f.location, !f.entries.is_empty())
  }
  for s in m.unknown {
    w.text("$\{s.name}\n")
    w.text(s.body)
    if !s.body.is_empty() && !s.body.has_suffix("\n") {
      w.text("\n")
    }
    w.end(s.name, false)
  }
  Bytes::from_array(w.out)
}
