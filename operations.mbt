///| Element subset; retain original tag/order supplied by caller, prune unused

///|
/// nodes and data entries. Entity graph and physical names remain as metadata.
pub fn Mesh::subset(self : Mesh, tags : Array[Int]) -> Mesh raise {
  if !self.unknown.is_empty() {
    bad("subset requires explicit removal of opaque sections")
  }
  if tags.length() > 1000000 {
    bad("subset request exceeds limit")
  }
  let selected : Map[Int, Bool] = Map([])
  let used : Map[Int, Bool] = Map([])
  let es = []
  for t in tags {
    if selected.contains(t) {
      bad("duplicate requested element")
    }
    let e = match self.ei.get(t) {
      Some(i) => self.es[i]
      None => {
        bad("unknown requested element \{t}")
        self.es[0]
      }
    }
    selected[t] = true
    es.push(e)
    for n in e.nodes {
      used[n] = true
    }
  }
  let ns = self.ns.filter(n => used.contains(n.tag))
  let fs = self.fs.map(f => {
    let entries = f.entries.filter(d => {
      if f.location == "NodeData" {
        used.contains(d.tag)
      } else {
        selected.contains(d.tag)
      }
    })
    let integers = f.integers.copy()
    integers[2] = entries.length()
    { ..f, entries, integers, }
  })
  mesh(
    ns,
    es,
    entities=self.ents,
    names=self.names,
    fields=fs,
    version=self.version,
  )
}

///|
pub fn Mesh::select_physical(self : Mesh, dim : Int, group : Int) -> Mesh raise {
  if dim < 0 || dim > 3 || group <= 0 {
    bad("invalid dimension/physical group")
  }
  let tags = []
  for e in self.es {
    if element_shape(e.kind).0 == dim && e.physical.contains(group) {
      tags.push(e.tag)
    }
  }
  self.subset(tags)
}

///| Dense tags follow stored order, starting at one; fields are remapped too.

///|
/// Entity/physical IDs are semantic labels and intentionally not renumbered.
pub fn Mesh::compact(self : Mesh) -> Mesh raise {
  if !self.unknown.is_empty() {
    bad("renumbering requires explicit removal of opaque sections")
  }
  let nm : Map[Int, Int] = Map([])
  let em : Map[Int, Int] = Map([])
  for i, n in self.ns {
    nm[n.tag] = i + 1
  }
  for i, e in self.es {
    em[e.tag] = i + 1
  }
  let ns = self.ns.map(n => { ..n, tag: nm[n.tag], })
  let es = self.es.map(e => {
    ..e,
    tag: em[e.tag],
    nodes: e.nodes.map(t => nm[t]),
  })
  let fs = self.fs.map(f => {
    ..f,
    entries: f.entries.map(d => {
      ..d,
      tag: if f.location == "NodeData" {
        nm[d.tag]
      } else {
        em[d.tag]
      },
    }),
  })
  mesh(
    ns,
    es,
    entities=self.ents,
    names=self.names,
    fields=fs,
    version=self.version,
  )
}

///|
pub(all) struct Facet {
  nodes : Array[Int]
  owners : Array[Int]
} derive(ToJson)

///|
pub extend Facet with ToJson::{to_json}

///|
pub(all) struct Topology {
  dimension : Int
  facets : Array[Facet]
  boundary : Array[Facet]
  nonmanifold : Array[Facet]
} derive(ToJson)

///|
pub extend Topology with ToJson::{to_json}

///| Outward faces for the positive Gmsh linear reference cell. Triangles/quads

///|
/// use oriented edges; a tetrahedron [0,1,2,3] has positive determinant.
fn local_facets(kind : Int) -> Array[Array[Int]] raise {
  match kind {
    15 => []
    1 => [[0], [1]]
    2 => [[0, 1], [1, 2], [2, 0]]
    3 => [[0, 1], [1, 2], [2, 3], [3, 0]]
    4 => [[0, 2, 1], [0, 1, 3], [1, 2, 3], [2, 0, 3]]
    5 =>
      [
        [0, 3, 2, 1],
        [4, 5, 6, 7],
        [0, 1, 5, 4],
        [1, 2, 6, 5],
        [2, 3, 7, 6],
        [3, 0, 4, 7],
      ]
    6 => [[0, 2, 1], [3, 4, 5], [0, 1, 4, 3], [1, 2, 5, 4], [2, 0, 3, 5]]
    7 => [[0, 3, 2, 1], [0, 1, 4], [1, 2, 4], [2, 3, 4], [3, 0, 4]]
    8 | 9 | 10 | 11 | 12 | 16 | 17 => quadratic_facets(kind)
    _ => {
      bad("unsupported high-order facet topology")
      []
    }
  }
}

///|
fn id_key(ids : Array[Int]) -> String {
  ids.map(i => i.to_string()).join(",")
}

///| Highest dimension by default; lower-dimensional explicit boundary cells

///| are not counted as adjacent volume cells. Each facet lists all incident

///|
/// element tags, avoiding quadratic neighbor expansion for nonmanifold input.
/// Matching node sets must also have the same polygon edge cycle. This rejects
/// incompatible quadrilateral connectivity before boundary/OBJ omit the face;
/// rotation and reversal remain valid, without certifying geometric orientation.
pub fn Mesh::topology(self : Mesh, dimension? : Int = -1) -> Topology raise {
  let mut dim = dimension
  if dim == -1 {
    for e in self.es {
      let d = element_shape(e.kind).0
      if d > dim {
        dim = d
      }
    }
  }
  if dim < -1 || dim > 3 {
    bad("invalid topology dimension")
  }
  let facets : Array[Facet] = []
  let index : Map[String, Int] = Map([])
  let mut count = 0
  for e in self.es {
    if element_shape(e.kind).0 != dim {
      continue
    }
    for face in local_facets(e.kind) {
      let nodes = face.map(i => e.nodes[i])
      let sorted = nodes.copy()
      sorted.sort()
      for j in 1..<sorted.length() {
        if sorted[j] == sorted[j - 1] {
          bad("repeated nodes in facet; run diagnostics first")
        }
      }
      let key = facet_identity(nodes, dim - 1)
      match index.get(key) {
        Some(i) => {
          if !compatible_facet(facets[i].nodes, nodes, dim - 1) {
            bad("shared facet has incompatible polygon order")
          }
          facets[i].owners.push(e.tag)
        }
        None => {
          index[key] = facets.length()
          facets.push({ nodes, owners: [e.tag], })
        }
      }
      count = count + 1
      if count > 6000000 {
        bad("topology incidence limit")
      }
    }
  }
  {
    dimension: dim,
    facets,
    boundary: facets.filter(f => f.owners.length() == 1),
    nonmanifold: facets.filter(f => f.owners.length() > 2),
  }
}

///|
fn root(parent : Array[Int], i : Int) -> Int {
  let mut j = i
  while parent[j] != j {
    parent[j] = parent[parent[j]]
    j = parent[j]
  }
  j
}

///| Components use shared nodes (not only full faces) and include all dimensions

///|
/// and orders. Isolated unused nodes are reported separately by diagnostics.
pub fn Mesh::components(self : Mesh) -> Array[Array[Int]] {
  let parent = Array::makei(self.es.length(), i => i)
  let rank = Array::make(self.es.length(), 0)
  let first : Map[Int, Int] = Map([])
  for i, e in self.es {
    for tag in e.nodes {
      match first.get(tag) {
        Some(j) => {
          let a = root(parent, i)
          let b = root(parent, j)
          if a != b {
            if rank[a] < rank[b] {
              parent[a] = b
            } else {
              parent[b] = a
              if rank[a] == rank[b] {
                rank[a] = rank[a] + 1
              }
            }
          }
        }
        None => first[tag] = i
      }
    }
  }
  let out : Array[Array[Int]] = []
  let groups : Map[Int, Int] = Map([])
  for i, e in self.es {
    let r = root(parent, i)
    match groups.get(r) {
      Some(j) => out[j].push(e.tag)
      None => {
        groups[r] = out.length()
        out.push([e.tag])
      }
    }
  }
  out
}
