///|
/// Source indices and local facet indices are zero-based; tags are unchanged.
/// explicit_element=0 means a new facet, not a source element with tag zero.
pub(all) struct BoundarySource {
  element : Int
  owner : Int
  owner_index : Int
  local_facet : Int
  explicit_element : Int
} derive(ToJson)

///|
pub extend BoundarySource with ToJson::{to_json}

///|
pub(all) struct BoundaryNode {
  tag : Int
  source_index : Int
} derive(ToJson)

///|
pub extend BoundaryNode with ToJson::{to_json}

///|
pub(all) struct BoundaryField {
  source_index : Int
  input_entries : Int
  retained_entries : Int
} derive(ToJson)

///|
pub extend BoundaryField with ToJson::{to_json}

///|
pub(all) struct BoundaryReport {
  source_dimension : Int
  boundary_dimension : Int
  selected_elements : Int
  nodes : Array[BoundaryNode]
  facets : Array[BoundarySource]
  fields : Array[BoundaryField]
  losses : Array[String]
} derive(ToJson)

///|
pub extend BoundaryReport with ToJson::{to_json}

///|
/// Owned result. Inspect the loss report before requesting the derived mesh.
pub struct Boundary {
  priv output : Mesh
  priv summary : BoundaryReport
  priv orientation_details : Array[FacetOrientation]
}

///|
pub fn Boundary::report(self : Boundary) -> BoundaryReport {
  {
    ..self.summary,
    nodes: self.summary.nodes.copy(),
    facets: self.summary.facets.copy(),
    fields: self.summary.fields.copy(),
    losses: self.summary.losses.copy(),
  }
}

///|
/// A derived, unclassified 2.2 model: matched facet labels and sparse fields
/// survive. Entity graphs/parameters and excluded data are never silently lost.
/// Later encode/VTK/OBJ calls apply their own independent loss gates too.
pub fn Boundary::mesh(
  self : Boundary,
  allow_loss? : Bool = false,
) -> Mesh raise {
  if !allow_loss && !self.summary.losses.is_empty() {
    bad(
      "boundary extraction requires allow_loss: " +
      self.summary.losses.join(", "),
    )
  }
  self.output
}

///|
fn facet_key(nodes : Array[Int]) -> String {
  let sorted = nodes.copy()
  sorted.sort()
  id_key(sorted)
}

///|
/// Same polygon up to rotation/reversal, not merely the same node set.
fn same_cycle(a : Array[Int], b : Array[Int]) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for offset in 0..<b.length() {
    let mut forward = true
    let mut backward = true
    for i in 0..<a.length() {
      forward = forward && a[i] == b[(offset + i) % b.length()]
      backward = backward && a[i] == b[(offset + b.length() - i) % b.length()]
    }
    if forward || backward {
      return true
    }
  }
  false
}

///|
/// Extract incidence-one facets at one dimension (highest by default).
/// New facets follow the source reference-cell winding, NOT a certified outward
/// normal on inverted/warped cells. Matching explicit facets retain their own
/// winding, tags, elementary/physical IDs, extra tags and ElementData.
/// NodeData is restricted by unchanged node tags; parent ElementData is not
/// interpolated or copied across dimensions. Use report() for every omission.
/// Retain supported quadratic selected cells/codimension-one elements. Reject unsupported families, duplicate cells,
/// nonmanifold incidence and ambiguous explicit matches, even with allow_loss.
pub fn Mesh::extract_boundary(
  self : Mesh,
  dimension? : Int = -1,
  max_facets? : Int = 1000000,
) -> Boundary raise {
  if !self.unknown.is_empty() {
    bad("boundary extraction requires explicit removal of opaque sections")
  }
  if max_facets < 0 || max_facets > 1000000 {
    bad("max_facets must be 0..1000000")
  }
  let mut dim = dimension
  if dim == -1 {
    for e in self.es {
      let d = element_shape(e.kind).0
      if d > dim {
        dim = d
      }
    }
  }
  if dim < 1 || dim > 3 {
    bad("boundary source dimension must be 1, 2 or 3")
  }
  let seen : Map[String, Bool] = Map([])
  let explicit : Map[String, Array[Int]] = Map([])
  let mut selected = 0
  for i, e in self.es {
    let d = element_shape(e.kind).0
    if d != dim && d != dim - 1 {
      continue
    }
    ignore(local_facets(e.kind)) // Check supported family; never strip curved nodes.
    let sorted = e.nodes.copy()
    sorted.sort()
    for j in 1..<sorted.length() {
      if sorted[j] == sorted[j - 1] {
        bad("repeated nodes in boundary source element")
      }
    }
    let key = if d == dim {
      id_key(sorted)
    } else {
      facet_identity(e.nodes, dim - 1)
    }
    if d == dim {
      selected = selected + 1
      let cell_key = "\{e.kind}:" + key
      if seen.contains(cell_key) {
        bad("duplicate source cell in boundary extraction")
      }
      seen[cell_key] = true
    } else {
      match explicit.get(key) {
        Some(ids) => ids.push(i)
        None => explicit[key] = [i]
      }
    }
  }
  if selected == 0 {
    bad("no elements at boundary source dimension")
  }
  let topology = self.topology(dimension=dim)
  if !topology.nonmanifold.is_empty() {
    bad("nonmanifold incidence in boundary extraction")
  }
  if topology.boundary.length() > max_facets {
    bad("boundary facet budget exceeded; no partial mesh returned")
  }
  let orientation_details : Array[FacetOrientation] = []
  let es : Array[Element] = []
  let sources : Array[BoundarySource] = []
  let used : Map[Int, Bool] = Map([])
  let retained : Map[Int, Bool] = Map([])
  let mut next = 1
  for f in topology.boundary {
    let owner_index = self.ei[f.owners[0]]
    let owner = self.es[owner_index]
    let mut local_facet = -1
    for i, corners in local_facets(owner.kind) {
      if corners.map(j => owner.nodes[j]) == f.nodes {
        local_facet = i
        break
      }
    }
    let matches = explicit.get(facet_identity(f.nodes, dim - 1)).unwrap_or([])
    if matches.length() > 1 {
      bad("ambiguous explicit boundary facet")
    }
    let mut explicit_element = 0
    let e = if matches.length() == 1 {
      let e = self.es[matches[0]]
      if !compatible_facet(e.nodes, f.nodes, dim - 1) {
        bad("explicit facet has incompatible polygon order")
      }
      explicit_element = e.tag
      retained[e.tag] = true
      e
    } else {
      // At most 1M occupied source tags + 1M output tags: no signed-32 overflow,
      // including inputs that already contain the maximum tag 2147483647.
      while self.ei.contains(next) {
        next = next + 1
      }
      let tag = next
      next = next + 1
      Element::{
        tag,
        kind: facet_kind(f.nodes, dim - 1),
        nodes: f.nodes.copy(),
        entity: 0,
        physical: [],
        extra: [],
      }
    }
    orientation_details.push(
      self.facet_orientation(e, owner, f.nodes, dim) catch {
        _ =>
          {
            element: e.tag,
            owner: owner.tag,
            explicit_reversed: facet_reversed(e.nodes, f.nodes, dim - 1),
            center_normal: [],
            center_dot: 0.0,
            status: "unavailable_numeric_range",
          }
      },
    )
    es.push(e)
    for tag in e.nodes {
      used[tag] = true
    }
    sources.push({
      element: e.tag,
      owner: owner.tag,
      owner_index,
      local_facet,
      explicit_element,
    })
  }
  let node_map : Array[BoundaryNode] = []
  let ns : Array[Node] = []
  let mut classified = false
  for i, n in self.ns {
    if used.contains(n.tag) {
      node_map.push({ tag: n.tag, source_index: i, })
      classified = classified || n.dim != -1 || !n.parameters.is_empty()
      ns.push({ ..n, dim: -1, entity: 0, parameters: [], })
    }
  }
  let fields : Array[BoundaryField] = []
  let fs : Array[Field] = []
  let losses : Array[String] = []
  if !self.ents.is_empty() || classified {
    losses.push("entity_graph_and_node_classification")
  }
  if self.es.any(e => {
      !retained.contains(e.tag) &&
      (e.entity != 0 || !e.physical.is_empty() || !e.extra.is_empty())
    }) {
    losses.push("excluded_element_labels_not_inherited")
  }
  for i, f in self.fs {
    let entries = f.entries.filter(d => {
      if f.location == "NodeData" {
        used.contains(d.tag)
      } else {
        retained.contains(d.tag)
      }
    })
    fields.push({
      source_index: i,
      input_entries: f.entries.length(),
      retained_entries: entries.length(),
    })
    if entries.length() != f.entries.length() {
      losses.push("field_entries:\{i}")
    }
    let integers = f.integers.copy()
    integers[2] = entries.length()
    fs.push({ ..f, entries, integers, })
  }
  let physical : Map[Int, Bool] = Map([])
  for e in es {
    for tag in e.physical {
      physical[tag] = true
    }
  }
  let names = self.names.filter(n => {
    n.dim == dim - 1 && physical.contains(n.tag)
  })
  if names.length() != self.names.length() {
    losses.push("unused_physical_names")
  }
  {
    output: mesh(ns, es, names~, fields=fs),
    orientation_details,
    summary: {
      source_dimension: dim,
      boundary_dimension: dim - 1,
      selected_elements: selected,
      nodes: node_map,
      facets: sources,
      fields,
      losses,
    },
  }
}
