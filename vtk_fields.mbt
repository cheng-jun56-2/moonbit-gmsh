///|
/// One selected source section and its safe VTK array alias. Raw heads are
/// owned copies; original names/times are not inferred from the array alias.
pub(all) struct VtkFieldArray {
  field : FieldFrame
  value_array : String
  strings : Array[String]
  reals : Array[Double]
  integers : Array[Int]
} derive(ToJson)

///|
pub extend VtkFieldArray with ToJson::{to_json}

///|
pub(all) struct VtkFieldsExport {
  text : String
  fields : Array[VtkFieldArray]
  source_version : String
  omitted_field_indices : Array[Int]
  losses : Array[String]
} derive(ToJson)

///|
pub extend VtkFieldsExport with ToJson::{to_json}

///|
priv struct VtkFieldsPlan {
  index : Int
  data : Field
  values : Map[Int, Array[Double]]
}

///|
/// Explicit same-Mesh frames, not a time alignment/merge operation. Report order
/// follows requested indices; arrays are grouped POINT_DATA then CELL_DATA,
/// retaining filtered request order. gmsh_value_I uses current source index I.
/// Each selected association has exactly one original-ID gmsh_tag array.
pub fn Mesh::vtk_fields(
  self : Mesh,
  field_indices : Array[Int],
  allow_loss? : Bool = false,
) -> VtkFieldsExport raise {
  if field_indices.is_empty() || field_indices.length() > 1024 {
    bad("VTK fields requires 1..1024 source indices; use vtk for geometry only")
  }
  let selected : Map[Int, Bool] = Map([])
  for index in field_indices {
    if index < 0 || index >= self.fs.length() {
      bad("VTK fields source index is out of range")
    }
    if selected.contains(index) {
      bad("duplicate VTK fields source index")
    }
    selected[index] = true
  }
  self.export_gate(allow_loss)
  let node_tags = self.ns.map(n => n.tag)
  let cell_tags = self.es.map(e => e.tag)
  let plans : Array[VtkFieldsPlan] = []
  for index in field_indices {
    let data = self.fs[index]
    let tags = if data.location == "NodeData" { node_tags } else { cell_tags }
    let values : Map[Int, Array[Double]] = Map([])
    for datum in data.entries {
      values[datum.tag] = datum.values
    }
    for tag in tags {
      if !values.contains(tag) {
        bad("VTK fields source index \{index} is missing tag \{tag}")
      }
    }
    plans.push({ index, data, values, })
  }
  let w : Writer = { out: [], binary: false, little: true, width: 8, }
  w.text(self.vtk_geometry("MoonGmsh selected-fields export"))
  for nodal in [true, false] {
    let group = plans.filter(p => (p.data.location == "NodeData") == nodal)
    if group.is_empty() {
      continue
    }
    let tags = if nodal { node_tags } else { cell_tags }
    let association = if nodal { "POINT_DATA" } else { "CELL_DATA" }
    w.text(
      "\{association} \{tags.length()}\nFIELD FieldData \{group.length() + 1}\n",
    )
    for plan in group {
      w.text(
        "gmsh_value_\{plan.index} \{plan.data.integers[1]} \{tags.length()} double\n",
      )
      for tag in tags {
        for i, value in plan.values[tag] {
          if i > 0 {
            w.text(" ")
          }
          // Keep the existing numeric text policy, including signed-zero
          // normalization; this export does not promise bitwise encoding.
          w.text("\{value}")
        }
        w.text("\n")
      }
    }
    w.text("gmsh_tag 1 \{tags.length()} int\n")
    for tag in tags {
      w.text("\{tag}\n")
    }
  }
  let has_node = plans.any(p => p.data.location == "NodeData")
  let has_cell = plans.any(p => p.data.location == "ElementData")
  let omitted : Array[Int] = []
  for i = 0; i < self.fs.length(); i = i + 1 {
    if !selected.contains(i) {
      omitted.push(i)
    }
  }
  let losses = ["msh_field_headers_not_in_vtk"]
  if (!has_node && !self.ns.is_empty()) || (!has_cell && !self.es.is_empty()) {
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
  let fields : Array[VtkFieldArray] = plans.map(p => {
    field: field_frame_info(p.data, p.index),
    value_array: "gmsh_value_\{p.index}",
    strings: p.data.strings.copy(),
    reals: p.data.reals.copy(),
    integers: p.data.integers.copy(),
  })
  {
    text: @utf8.decode(Bytes::from_array(w.out)),
    fields,
    source_version: self.version,
    omitted_field_indices: omitted,
    losses,
  }
}
