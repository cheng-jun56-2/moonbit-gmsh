///|
/// Corner-only planar output is deliberately explicit. Strict refuses every
/// reported loss; permissive output always travels together with its audit.
pub(all) enum ExportPolicy {
  Strict
  PermissiveWithAudit
}

///|
pub(all) struct LossReport {
  source_dimension : Int
  discarded_curved_node_tags : Array[Int]
  losses : Array[String]
  estimated_chord_error : Double
  error_samples : Int
  error_measure : String
  certified_bound : Bool
  output_vertices : Int
  output_elements : Int
  orientations : Array[FacetOrientation]
} derive(ToJson)

///|
pub extend LossReport with ToJson::{to_json}

///|
/// Difference from the actual planar output, evaluated algebraically in a
/// common frame. Subtracting two separately rounded absolute positions makes
/// an O(epsilon) false deviation hide a real 1e-200 face-center displacement.
fn Mesh::planar_deviation(
  self : Mesh,
  e : Element,
  p : Array[Double],
) -> Double raise {
  let delta = [scaled(0.0), scaled(0.0), scaled(0.0)]
  if e.kind == 8 || e.kind == 9 || e.kind == 10 || e.kind == 16 {
    let b = basis(e.kind, p)
    let residual = self.quadratic_remainders(e)
    for i in primary_count(e.kind)..<e.nodes.length() {
      for k in 0..<3 {
        delta[k] = delta[k].plus(residual[i][k].times(scaled(b[i].v)))
      }
    }
  }
  if e.kind == 3 || e.kind == 10 || e.kind == 16 {
    let a = (p[0] + 1.0) / 2.0
    let b = (p[1] + 1.0) / 2.0
    let coefficient = -a.min(b) * (1.0 - a.max(b))
    let pts = e.nodes[:4].map(t => self.ns[self.ni[t]].xyz)
    let d2 = scaled_difference(pts[2], pts[1])
    let d3 = scaled_difference(pts[3], pts[0])
    for k in 0..<3 {
      delta[k] = delta[k].plus(
        d2[k].plus(d3[k].negative()).times(scaled(coefficient)),
      )
    }
  }
  scaled_norm(delta).value("export approximation error")
}

///|
fn Mesh::audited_surface(
  self : Mesh,
  policy : ExportPolicy,
  stl : Bool,
) -> (String, LossReport) raise {
  let mut dim = 0
  for e in self.es {
    dim = dim.max(element_shape(e.kind).0)
  }
  if stl && dim < 2 {
    bad("STL requires a surface or volume boundary")
  }
  let losses : Array[String] = []
  let mut orientations : Array[FacetOrientation] = []
  let surf = if dim == 3 {
    let b = self.extract_boundary()
    for s in b.report().losses {
      losses.push("boundary:" + s)
    }
    orientations = b.orientation_report()
    b.mesh(allow_loss=true)
  } else {
    self
  }
  if !self.fs.is_empty() ||
    !self.ents.is_empty() ||
    !self.names.is_empty() ||
    !self.unknown.is_empty() ||
    self.ns.any(n => n.dim != -1 || !n.parameters.is_empty()) ||
    self.es.any(e => {
      e.entity != 0 || !e.physical.is_empty() || !e.extra.is_empty()
    }) {
    losses.push("metadata_omitted")
  }
  let kept : Map[Int, Bool] = Map([])
  let curved : Map[Int, Bool] = Map([])
  let rows : Array[Array[Int]] = []
  let mut maximum = 0.0
  let mut samples = 0
  let target_dim = if dim == 3 { 2 } else { dim }
  let mut skipped = 0
  let mut quads = false
  for e in surf.es {
    let d = element_shape(e.kind).0
    if d != target_dim {
      skipped = skipped + 1
      continue
    }
    if ![1, 2, 3, 8, 9, 10, 15, 16].contains(e.kind) {
      bad("unsupported audited surface family")
    }
    let c = if d == 0 { 1 } else { facet_corners(e.nodes.length(), d) }
    for i, t in e.nodes {
      if i < c {
        kept[t] = true
      } else {
        curved[t] = true
      }
    }
    if c == 4 {
      quads = true
      rows.push([e.nodes[0], e.nodes[1], e.nodes[2]])
      rows.push([e.nodes[0], e.nodes[2], e.nodes[3]])
    } else {
      rows.push(e.nodes[:c].to_owned())
    }
    if e.kind == 8 || e.kind == 9 || e.kind == 10 || e.kind == 16 {
      let ps = reference_nodes(e.kind)
      for p in gauss2(e.kind) {
        ps.push(p)
      }
      for p in ps {
        let distance = surf.planar_deviation(e, p)
        if !finite(distance) {
          bad("export approximation error outside finite Double range")
        }
        maximum = maximum.max(distance)
        samples = samples + 1
      }
    } else if e.kind == 3 {
      // For a warped linear quadrangle, the original bilinear patch differs
      // from the two planar output triangles even without midside nodes.
      for p in gauss2(10) {
        let distance = surf.planar_deviation(e, p)
        maximum = maximum.max(distance)
        samples = samples + 1
      }
    }
  }
  if skipped > 0 {
    losses.push("lower_dimension_elements_omitted")
  }
  if quads {
    losses.push("quad_triangulation_diagonal_0_2")
  }
  let removed : Array[Int] = []
  for t, _ in curved {
    if !kept.contains(t) {
      removed.push(t)
    }
  }
  // Connectivity is linearized even when another element keeps the same tag
  // as an output corner. Vertex omission and loss of interpolation differ.
  if !curved.is_empty() {
    losses.push("curved_connectivity_linearized")
  }
  removed.sort()
  if !removed.is_empty() {
    losses.push("curved_nodes_removed")
  }
  if self.ns.length() > kept.length() {
    losses.push("unreferenced_output_nodes_omitted")
  }
  let degenerate = rows.any(row => {
    if row.length() != 3 {
      false
    } else {
      let pts = row.map(t => surf.ns[surf.ni[t]].xyz)
      scaled_triangle_cross(pts).all(x => x.mantissa == 0.0)
    }
  })
  if degenerate {
    losses.push("degenerate_output_triangles")
  }
  if policy is Strict && !losses.is_empty() {
    bad("strict planar export refuses loss: " + losses.join(", "))
  }
  let tags : Array[Int] = []
  let indices : Map[Int, Int] = Map([])
  for n in surf.ns {
    if kept.contains(n.tag) {
      tags.push(n.tag)
      indices[n.tag] = tags.length()
    }
  }
  let sb : Writer = { out: [], binary: false, little: true, width: 8, }
  if stl {
    sb.text("solid MoonGmsh\n")
  } else {
    sb.text("# MoonGmsh audited corner-only planar geometry\n")
    for t in tags {
      let p = surf.ns[surf.ni[t]].xyz
      sb.text("v \{p[0]} \{p[1]} \{p[2]}\n")
    }
  }
  for row in rows {
    if stl {
      let pts = row.map(t => surf.ns[surf.ni[t]].xyz)
      let n = scaled_unit(scaled_triangle_cross(pts))
      sb.text("facet normal \{n[0]} \{n[1]} \{n[2]}\nouter loop\n")
      for p in pts {
        sb.text("vertex \{p[0]} \{p[1]} \{p[2]}\n")
      }
      sb.text("endloop\nendfacet\n")
    } else {
      let op = match row.length() {
        1 => "p"
        2 => "l"
        _ => "f"
      }
      sb.text(op)
      for t in row {
        sb.text(" \{indices[t]}")
      }
      sb.text("\n")
    }
  }
  if stl {
    sb.text("endsolid MoonGmsh\n")
  }
  (
    @utf8.decode(Bytes::from_array(sb.out)),
    {
      source_dimension: dim,
      discarded_curved_node_tags: removed,
      losses,
      estimated_chord_error: maximum,
      error_samples: samples,
      error_measure: "maximum sampled parameter-correspondence deviation (reference nodes + family Gauss2/CompositeGauss2); not a Hausdorff bound",
      certified_bound: false,
      output_vertices: tags.length(),
      output_elements: rows.length(),
      orientations,
    },
  )
}

///|
pub fn Mesh::export_to_obj(
  self : Mesh,
  policy : ExportPolicy,
) -> (String, LossReport) raise {
  self.audited_surface(policy, false)
}

///|
pub fn Mesh::export_to_stl(
  self : Mesh,
  policy : ExportPolicy,
) -> (String, LossReport) raise {
  self.audited_surface(policy, true)
}
