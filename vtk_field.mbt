///|
/// Keep this sidecar with text: VTK arrays contain selected values and only
/// their association's original tags, not MSH time/scheme/entity semantics.
pub(all) struct VtkFieldExport {
  text : String
  field : FieldFrame
  source_version : String
  strings : Array[String]
  reals : Array[Double]
  integers : Array[Int]
  omitted_field_indices : Array[Int]
  losses : Array[String]
} derive(ToJson)

///|
pub extend VtkFieldExport with ToJson::{to_json}

///|
/// One exact stored frame as generic FIELD arrays gmsh_value and gmsh_tag.
/// NodeData covers all stored nodes, including isolated nodes; ElementData
/// covers every cell. No zero filling, geometric pruning, interpolation or
/// vector/tensor interpretation. Fixed aliases allow arbitrary source names.
pub fn Mesh::vtk_field(
  self : Mesh,
  field_index : Int,
  allow_loss? : Bool = false,
) -> VtkFieldExport raise {
  if field_index < 0 || field_index >= self.fs.length() {
    bad("VTK field_index is out of range")
  }
  // A selected frame still has MSH headers that VTK does not carry. The
  // existing opt-in gate also covers unknown/group/entity metadata omissions.
  self.export_gate(allow_loss)
  let f = self.fs[field_index]
  let nodal = f.location == "NodeData"
  let tags = if nodal {
    self.ns.map(n => n.tag)
  } else {
    self.es.map(e => e.tag)
  }
  let values : Map[Int, Array[Double]] = Map([])
  for d in f.entries {
    values[d.tag] = d.values
  }
  for tag in tags {
    if !values.contains(tag) {
      bad("VTK field is missing tag \{tag}")
    }
  }
  let w : Writer = { out: [], binary: false, little: true, width: 8, }
  // Both geometry and attributes pass through one capped output Writer.
  w.text(self.vtk_geometry("MoonGmsh selected-field export"))
  let association = if nodal { "POINT_DATA" } else { "CELL_DATA" }
  w.text("\{association} \{tags.length()}\nFIELD FieldData 2\n")
  w.text("gmsh_value \{f.integers[1]} \{tags.length()} double\n")
  for tag in tags {
    for i, v in values[tag] {
      if i > 0 {
        w.text(" ")
      }
      w.text("\{v}")
    }
    w.text("\n")
  }
  // Model tags are positive signed32; int preserves even2147483647 exactly.
  w.text("gmsh_tag 1 \{tags.length()} int\n")
  for tag in tags {
    w.text("\{tag}\n")
  }
  let omitted : Array[Int] = []
  for i = 0; i < self.fs.length(); i = i + 1 {
    if i != field_index {
      omitted.push(i)
    }
  }
  let losses = ["msh_field_headers_not_in_vtk"]
  if (nodal && !self.es.is_empty()) || (!nodal && !self.ns.is_empty()) {
    losses.push("other_association_tags_not_in_vtk")
  }
  if !omitted.is_empty() {
    losses.push("other_field_sections_omitted")
  }
  if !self.ents.is_empty() ||
    !self.names.is_empty() ||
    !self.unknown.is_empty() ||
    self.ns.any(n => n.dim != -1 || !n.parameters.is_empty()) ||
    self.es.any(e => {
      e.entity != 0 || !e.physical.is_empty() || !e.extra.is_empty()
    }) {
    losses.push("mesh_metadata_omitted")
  }
  {
    text: @utf8.decode(Bytes::from_array(w.out)),
    field: field_frame_info(f, field_index),
    source_version: self.version,
    strings: f.strings.copy(),
    reals: f.reals.copy(),
    integers: f.integers.copy(),
    omitted_field_indices: omitted,
    losses,
  }
}
