///|
/// One standard P1 NodeData value at a supplied TET4 reference point.
/// Original tags/headers and four role witnesses are owned copies. xyz is a
/// forward parameter map, not an inverse, geometry or source certificate.
pub(all) struct Tet4FieldEvaluation {
  field : FieldFrame
  source_version : String
  element_tag : Int
  element_type : Int
  node_tags : Array[Int]
  reference : Array[Double]
  weights : Array[Double]
  node_xyz : Array[Array[Double]]
  nodal_values : Array[Array[Double]]
  xyz : Array[Double]
  values : Array[Double]
  strings : Array[String]
  reals : Array[Double]
  integers : Array[Int]
} derive(ToJson)

///|
pub extend Tet4FieldEvaluation with ToJson::{to_json}

///|
// Scaled::value exposes a generic error effect but its sole failure is this
// existing range rejection. Keep the new public query's typed MeshError effect.
fn tet4_numeric_value(value : Scaled, label : String) -> Double raise MeshError {
  value.value(label) catch {
    _ => raise Invalid("\{label} outside representable Double range")
  }
}

///|
/// Exact current frame index and same-Mesh element tag; only type4/NodeData.
/// Closed-simplex gate and w0 use the same Double sum (r+s)+t, with no epsilon
/// or clamp. All unique role data are required, including zero-weight roles.
/// Protected-range compensated sums are not exact arithmetic/error bounds.
pub fn Mesh::evaluate_tet4_nodal_field(
  self : Mesh,
  field_index : Int,
  element_tag : Int,
  reference : Array[Double],
) -> Tet4FieldEvaluation raise MeshError {
  if field_index < 0 || field_index >= self.fs.length() {
    bad("TET4 field index out of range")
  }
  let e = match self.ei.get(element_tag) {
    Some(index) => self.es[index]
    None => raise Invalid("TET4 unknown element tag")
  }
  if e.kind != 4 {
    bad("TET4 field evaluation requires element type4")
  }
  let f = self.fs[field_index]
  if f.location != "NodeData" {
    bad("TET4 field evaluation requires NodeData")
  }
  if f.strings.length() > 1 && !f.strings[1].is_empty() {
    bad("TET4 field evaluation does not interpret named schemes")
  }
  if reference.length() != 3 || reference.any(x => !finite(x) || x < 0.0) {
    bad("TET4 reference requires three finite nonnegative coordinates")
  }
  let sum = reference[0] + reference[1] + reference[2]
  if !finite(sum) || sum > 1.0 {
    bad("TET4 reference outside closed simplex")
  }
  let weights = [1.0 - sum, reference[0], reference[1], reference[2]]
  let required : Map[Int, Bool] = Map([])
  for tag in e.nodes {
    required[tag] = true
  }
  let data : Map[Int, Array[Double]] = Map([])
  for datum in f.entries {
    if required.contains(datum.tag) {
      data[datum.tag] = datum.values
    }
  }
  let coords : Map[Int, Array[Double]] = Map([])
  for tag in e.nodes {
    if !data.contains(tag) {
      bad("TET4 field missing required node tag \{tag}")
    }
    coords[tag] = self.ns[self.ni[tag]].xyz
  }
  // Reuse only the pure sorted/compensated nodal sum: jconst.v carries these
  // four P1 weights. No surface plan, derivative or 2D precondition is used.
  let basis_weights = weights.map(jconst)
  let values = [
    for component in 0..<f.integers[1] => {
      tet4_numeric_value(
        surface_nodal_value(e, basis_weights, data, component),
        "TET4 field value",
      )
    }
  ]
  let xyz = [
    for component in 0..<3 => {
      tet4_numeric_value(
        surface_nodal_value(e, basis_weights, coords, component),
        "TET4 mapped xyz",
      )
    }
  ]
  {
    field: field_frame_info(f, field_index),
    source_version: self.version,
    element_tag,
    element_type: 4,
    node_tags: e.nodes.copy(),
    reference: reference.copy(),
    weights,
    node_xyz: e.nodes.map(tag => coords[tag].copy()),
    nodal_values: e.nodes.map(tag => data[tag].copy()),
    xyz,
    values,
    strings: f.strings.copy(),
    reals: f.reals.copy(),
    integers: f.integers.copy(),
  }
}
