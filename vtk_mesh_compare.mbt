///|
/// Saved exported geometry plus the unchanged complete field readback.
/// Source tag arrays are supplied-source order witnesses, not a claim that an
/// omitted association's tags or full MSH metadata were embedded in VTK.
pub(all) struct VtkMeshReadback {
  fields : VtkFieldsReadback
  source_node_tags : Array[Int]
  source_element_tags : Array[Int]
  points : Array[Array[Double]]
  connectivity : Array[Array[Int]]
  cell_types : Array[Int]
} derive(ToJson)

///|
pub extend VtkMeshReadback with ToJson::{to_json}

///|
// The actual profile was validated by verify_vtk_fields; the expected stream
// comes from the existing exporter. Do not duplicate its type/permutation map.
fn vm_geometry_start(c : Cursor) -> Int raise {
  let _ = c.line()
  let _ = c.line()
  let _ = c.line()
  vr_expect(c, "DATASET")
  vr_expect(c, "UNSTRUCTURED_GRID")
  vr_expect(c, "POINTS")
  let count = vr_count(c)
  vr_expect(c, "double")
  count
}

///|
/// Verify the existing saved vtk_fields profile against this explicit source,
/// including every point (also isolated), ordered VTK role index and cell type.
/// Exact decoded numeric equality treats signed zero as equal; no tolerance,
/// reordering, isomorphism, geometric/physical validity or authenticity claim.
pub fn Mesh::verify_vtk_mesh(
  self : Mesh,
  data : Bytes,
  audit : Json,
) -> VtkMeshReadback raise {
  let fields = self.verify_vtk_fields(data, audit)
  let actual : Cursor = { data, p: 0, binary: false, little: true, width: 8, }
  let expected : Cursor = {
    data: @utf8.encode(self.vtk_geometry("source representation")),
    p: 0,
    binary: false,
    little: true,
    width: 8,
  }
  if vm_geometry_start(actual) != self.ns.length() ||
    vm_geometry_start(expected) != self.ns.length() {
    bad("VTK source point count differs")
  }
  let points = [
    for index in 0..<self.ns.length() => {
      [
        for _ in 0..<3 => {
          let value = actual.ar()
          if value != expected.ar() {
            bad("VTK source coordinates differ at point index \{index}")
          }
          value
        }
      ]
    }
  ]
  vr_expect(actual, "CELLS")
  vr_expect(expected, "CELLS")
  if actual.ai() != expected.ai() || actual.ai() != expected.ai() {
    bad("VTK source cell count/size differs")
  }
  let connectivity = [
    for index in 0..<self.es.length() => {
      let count = actual.ai()
      if count != expected.ai() {
        bad("VTK source cell arity differs at cell index \{index}")
      }
      [
        for _ in 0..<count => {
          let point = actual.ai()
          if point != expected.ai() {
            bad("VTK source ordered roles differ at cell index \{index}")
          }
          point
        }
      ]
    }
  ]
  vr_expect(actual, "CELL_TYPES")
  vr_expect(expected, "CELL_TYPES")
  if actual.ai() != expected.ai() {
    bad("VTK source cell type count differs")
  }
  let cell_types = [
    for index in 0..<self.es.length() => {
      let kind = actual.ai()
      if kind != expected.ai() {
        bad("VTK source cell type differs at cell index \{index}")
      }
      kind
    }
  ]
  {
    fields,
    source_node_tags: self.ns.map(n => n.tag),
    source_element_tags: self.es.map(e => e.tag),
    points,
    connectivity,
    cell_types,
  }
}
