///|
pub suberror MeshError {
  Invalid(String)
} derive(Debug)

///|
pub extend MeshError with @debug.Debug::{to_repr}

///|
pub(all) struct Node {
  tag : Int
  xyz : Array[Double]
  dim : Int
  entity : Int
  parameters : Array[Double]
} derive(ToJson)

///|
pub extend Node with ToJson::{to_json}

///|
pub(all) struct Element {
  tag : Int
  kind : Int
  nodes : Array[Int]
  entity : Int
  physical : Array[Int]
  extra : Array[Int]
} derive(ToJson)

///|
pub extend Element with ToJson::{to_json}

///|
pub(all) struct Entity {
  dim : Int
  tag : Int
  bounds : Array[Double]
  physical : Array[Int]
  boundary : Array[Int]
} derive(ToJson)

///|
pub extend Entity with ToJson::{to_json}

///|
pub(all) struct PhysicalName {
  dim : Int
  tag : Int
  name : String
} derive(ToJson)

///|
pub extend PhysicalName with ToJson::{to_json}

///|
pub(all) struct Datum {
  tag : Int
  values : Array[Double]
} derive(ToJson)

///|
pub extend Datum with ToJson::{to_json}

///|
pub(all) struct Field {
  location : String
  strings : Array[String]
  reals : Array[Double]
  integers : Array[Int]
  entries : Array[Datum]
} derive(ToJson)

///|
pub extend Field with ToJson::{to_json}

///|
pub(all) struct Section {
  name : String
  body : String
} derive(ToJson)

///|
pub extend Section with ToJson::{to_json}

///|
/// Owned snapshot. Public getters return deep copies; tag maps are never exposed.
pub struct Mesh {
  priv ns : Array[Node]
  priv es : Array[Element]
  priv ents : Array[Entity]
  priv names : Array[PhysicalName]
  priv fs : Array[Field]
  priv unknown : Array[Section]
  priv version : String
  priv ni : Map[Int, Int]
  priv ei : Map[Int, Int]
}

///|
fn bad(message : String) -> Unit raise MeshError {
  raise Invalid(message)
}

///|
fn finite(x : Double) -> Bool {
  x == x && x.abs() <= 1.7976931348623157e308
}

///|
fn positive(n : Int, what : String) -> Unit raise MeshError {
  if n <= 0 {
    bad("\{what}: tags must be positive signed 32-bit integers")
  }
}

///|
fn clean_name(s : String) -> Bool {
  !s.contains("\n") &&
  !s.contains("\r") &&
  !s.contains("\"") &&
  !s.contains("\\") &&
  !s.contains("\u0000")
}

///|
fn copy_node(n : Node) -> Node {
  { ..n, xyz: n.xyz.copy(), parameters: n.parameters.copy(), }
}

///|
fn copy_element(e : Element) -> Element {
  {
    ..e,
    nodes: e.nodes.copy(),
    physical: e.physical.copy(),
    extra: e.extra.copy(),
  }
}

///|
fn copy_entity(e : Entity) -> Entity {
  {
    ..e,
    bounds: e.bounds.copy(),
    physical: e.physical.copy(),
    boundary: e.boundary.copy(),
  }
}

///|
fn copy_field(f : Field) -> Field {
  {
    ..f,
    strings: f.strings.copy(),
    reals: f.reals.copy(),
    integers: f.integers.copy(),
    entries: f.entries.map(d => { ..d, values: d.values.copy(), }),
  }
}

///|
/// Gmsh's common first/second-order element IDs (manual MSH element table).
pub fn element_shape(kind : Int) -> (Int, Int) raise MeshError {
  match kind {
    1 => (1, 2)
    2 => (2, 3)
    3 => (2, 4)
    4 => (3, 4)
    5 => (3, 8)
    6 => (3, 6)
    7 => (3, 5)
    8 => (1, 3)
    9 => (2, 6)
    10 => (2, 9)
    11 => (3, 10)
    12 => (3, 27)
    13 => (3, 18)
    14 => (3, 14)
    15 => (0, 1)
    16 => (2, 8)
    17 => (3, 20)
    18 => (3, 15)
    19 => (3, 13)
    _ => {
      bad("unsupported element type \{kind}; common orders 1 and 2 only")
      (0, 0)
    }
  }
}

///| Portable resource contract: <=1M nodes/elements, 8M connectivity/data values.

///|
/// Geometry defects are retained for diagnostics; malformed references are not.
pub fn mesh(
  nodes : Array[Node],
  elements : Array[Element],
  entities? : Array[Entity] = [],
  names? : Array[PhysicalName] = [],
  fields? : Array[Field] = [],
  unknown? : Array[Section] = [],
  version? : String = "2.2",
) -> Mesh raise MeshError {
  if version != "2.2" && version != "4.1" {
    bad("version must be 2.2 or 4.1")
  }
  if nodes.length() > 1000000 ||
    elements.length() > 1000000 ||
    entities.length() > 1000000 ||
    fields.length() > 1024 ||
    unknown.length() > 1024 ||
    names.length() > 1000000 {
    bad("model resource limit")
  }
  let ni : Map[Int, Int] = Map([])
  let ei : Map[Int, Int] = Map([])
  let ent : Map[String, Entity] = Map([])
  for e in entities {
    positive(e.tag, "entity")
    let key = "\{e.dim}:\{e.tag}"
    if e.dim < 0 ||
      e.dim > 3 ||
      ent.contains(key) ||
      e.bounds.length() != (if e.dim == 0 { 3 } else { 6 }) {
      bad("invalid or duplicate entity")
    }
    if e.bounds.any(x => !finite(x)) ||
      e.physical.any(x => x <= 0) ||
      e.boundary.any(x => x == 0 || x == -2147483648) ||
      (e.dim == 0 && !e.boundary.is_empty()) {
      bad("invalid entity bounds/groups/boundary")
    }
    if e.dim > 0 {
      for j = 0; j < 3; j = j + 1 {
        if e.bounds[j] > e.bounds[j + 3] {
          bad("inverted entity bounding box")
        }
      }
    }
    ent[key] = e
  }
  for e in entities {
    for b in e.boundary {
      if !ent.contains("\{e.dim-1}:\{b.abs()}") {
        bad("missing entity boundary reference")
      }
    }
  }
  for i, n in nodes {
    positive(n.tag, "node")
    if ni.contains(n.tag) ||
      n.xyz.length() != 3 ||
      n.xyz.any(x => !finite(x)) ||
      n.parameters.any(x => !finite(x)) {
      bad("duplicate node or invalid coordinates")
    }
    if n.dim < -1 ||
      n.dim > 3 ||
      n.entity < 0 ||
      (n.dim == -1 && (n.entity != 0 || !entities.is_empty())) ||
      (!n.parameters.is_empty() && n.parameters.length() != n.dim) {
      bad("invalid node classification/parameters")
    }
    if n.dim >= 0 && (n.entity <= 0 || !ent.contains("\{n.dim}:\{n.entity}")) {
      bad("missing node entity")
    }
    ni[n.tag] = i
  }
  let mut links = 0
  for i, e in elements {
    positive(e.tag, "element")
    let (dim, width) = element_shape(e.kind)
    if ei.contains(e.tag) ||
      e.nodes.length() != width ||
      e.nodes.any(n => !ni.contains(n)) ||
      e.entity < 0 ||
      e.physical.any(p => p <= 0) {
      bad("invalid element tag, connectivity or group")
    }
    if !entities.is_empty() {
      match ent.get("\{dim}:\{e.entity}") {
        Some(entity) =>
          if entity.physical != e.physical {
            bad("element physical groups disagree with entity")
          }
        None => bad("missing element entity")
      }
    }
    links = links + width
    if links > 8000000 || e.extra.length() > 1024 {
      bad("connectivity/legacy tag limit")
    }
    ei[e.tag] = i
  }
  let seen : Map[String, Bool] = Map([])
  for n in names {
    let key = "\{n.dim}:\{n.tag}"
    if n.dim < 0 ||
      n.dim > 3 ||
      n.tag <= 0 ||
      !clean_name(n.name) ||
      n.name.length() > 127 ||
      seen.contains(key) {
      bad("invalid or duplicate physical name")
    }
    seen[key] = true
  }
  let mut values = 0
  for f in fields {
    if f.location != "NodeData" && f.location != "ElementData" {
      bad("field location must be NodeData or ElementData")
    }
    if f.strings.is_empty() ||
      f.strings.length() > 1024 ||
      f.strings.any(s => !clean_name(s) || s.length() > 4096) ||
      f.reals.length() > 1024 ||
      f.reals.any(x => !finite(x)) ||
      f.integers.length() < 3 ||
      f.integers.length() > 1024 {
      bad("invalid data header")
    }
    let nc = f.integers[1]
    if (nc != 1 && nc != 3 && nc != 9) ||
      f.integers[2] != f.entries.length() ||
      f.entries.length() > 1000000 {
      bad("data components/count must be 1,3,9 and match entries")
    }
    let ids : Map[Int, Bool] = Map([])
    for d in f.entries {
      if ids.contains(d.tag) ||
        !(if f.location == "NodeData" {
          ni.contains(d.tag)
        } else {
          ei.contains(d.tag)
        }) ||
        d.values.length() != nc ||
        d.values.any(x => !finite(x)) {
        bad("invalid field data or missing tag")
      }
      ids[d.tag] = true
      values = values + nc
      if values > 8000000 {
        bad("data value limit")
      }
    }
  }
  for s in unknown {
    if s.name.is_empty() ||
      s.name.length() > 128 ||
      !s.name
      .iter()
      .all(c => {
        (c >= 'A' && c <= 'Z') ||
        (c >= 'a' && c <= 'z') ||
        (c >= '0' && c <= '9') ||
        c == '_'
      }) ||
      s.name.has_prefix("End") ||
      [
        "MeshFormat", "Nodes", "Elements", "Entities", "PhysicalNames", "NodeData",
        "ElementData",
      ].contains(s.name) ||
      s.body.contains("$End\{s.name}") ||
      s.body.contains("\u0000") {
      bad("unsafe unknown section")
    }
  }
  {
    ns: nodes.map(copy_node),
    es: elements.map(copy_element),
    ents: entities.map(copy_entity),
    names: names.copy(),
    fs: fields.map(copy_field),
    unknown: unknown.copy(),
    version,
    ni,
    ei,
  }
}

///|
pub fn Mesh::nodes(self : Mesh) -> Array[Node] {
  self.ns.map(copy_node)
}

///|
pub fn Mesh::elements(self : Mesh) -> Array[Element] {
  self.es.map(copy_element)
}

///|
pub fn Mesh::entities(self : Mesh) -> Array[Entity] {
  self.ents.map(copy_entity)
}

///|
pub fn Mesh::physical_names(self : Mesh) -> Array[PhysicalName] {
  self.names.copy()
}

///|
pub fn Mesh::fields(self : Mesh) -> Array[Field] {
  self.fs.map(copy_field)
}

///|
pub fn Mesh::unknown_sections(self : Mesh) -> Array[Section] {
  self.unknown.copy()
}

///|
pub fn Mesh::source_version(self : Mesh) -> String {
  self.version
}

///|
pub fn Mesh::without_unknown(self : Mesh) -> Mesh {
  { ..self, unknown: [], }
}
