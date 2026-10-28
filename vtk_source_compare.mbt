///|
/// Compare a saved vtk_fields profile with this explicitly supplied source.
/// This is field equality, not geometry equivalence or source authentication.
/// Raw heads and current section indices are exact; numeric equality treats
/// signed zero as equivalent, following the existing VTK text policy.
pub fn Mesh::verify_vtk_fields(
  self : Mesh,
  data : Bytes,
  audit : Json,
) -> VtkFieldsReadback raise {
  let saved = read_vtk_fields(data, audit)
  if saved.source_version != self.version ||
    saved.points != self.ns.length() ||
    saved.cells != self.es.length() {
    bad("VTK source version/counts differ from the supplied Mesh")
  }
  if (saved.has_point_tags && saved.point_tags != self.ns.map(n => n.tag)) ||
    (saved.has_cell_tags && saved.cell_tags != self.es.map(e => e.tag)) {
    bad("VTK original tag order differs from the supplied Mesh")
  }
  let rows : Array[Json] = vr_get(vr_object(audit), "fields")
  let selected : Map[Int, Bool] = Map([])
  for position, item in saved.fields {
    let index = item.field.field_index
    if index >= self.fs.length() {
      bad("VTK selected source field index is out of range")
    }
    selected[index] = true
    let source = self.fs[index]
    let row = vr_object(rows[position])
    let strings : Array[String] = vr_get(row, "strings")
    let reals : Array[Double] = vr_get(row, "reals")
    let integers = vr_ints(row, "integers")
    if item.field.to_json() != field_frame_info(source, index).to_json() ||
      strings != source.strings ||
      reals != source.reals ||
      integers != source.integers {
      bad("VTK source field \{index} raw headers differ")
    }
    // Source entries may have any order; compare by their original tag.
    let expected : Map[Int, Array[Double]] = Map([])
    for datum in source.entries {
      expected[datum.tag] = datum.values
    }
    let tags = if source.location == "NodeData" {
      saved.point_tags
    } else {
      saved.cell_tags
    }
    for position, tag in tags {
      match expected.get(tag) {
        Some(values) if values == item.values[position] => ()
        _ => bad("VTK source field \{index} tuple differs at tag \{tag}")
      }
    }
  }
  let omitted = []
  for index in 0..<self.fs.length() {
    if !selected.contains(index) {
      omitted.push(index)
    }
  }
  if omitted != saved.omitted_field_indices {
    bad("VTK omitted field indices differ from the supplied Mesh")
  }
  saved
}
