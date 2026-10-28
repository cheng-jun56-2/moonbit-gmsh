///|
/// Saved values in the association's original tag order, with the exact frame.
pub(all) struct VtkFieldReadback {
  field : FieldFrame
  value_array : String
  values : Array[Array[Double]]
} derive(ToJson)

///|
pub extend VtkFieldReadback with ToJson::{to_json}

///|
/// A consistency readback of vtk_fields output, not a mesh/physics certificate.
/// has_* distinguishes an absent association from a selected zero-tuple one.
pub(all) struct VtkFieldsReadback {
  points : Int
  cells : Int
  has_point_tags : Bool
  has_cell_tags : Bool
  point_tags : Array[Int]
  cell_tags : Array[Int]
  fields : Array[VtkFieldReadback]
  source_version : String
  omitted_field_indices : Array[Int]
  losses : Array[String]
} derive(ToJson)

///|
pub extend VtkFieldsReadback with ToJson::{to_json}

///|
priv struct VtkReadPlan {
  frame : FieldFrame
  array_name : String
}

///|
fn vr_object(value : Json) -> Map[String, Json] raise {
  match value {
    Object(o) => o
    _ => raise Invalid("VTK sidecar requires an object")
  }
}

///|
fn[T : @json.FromJson] vr_get(o : Map[String, Json], key : String) -> T raise {
  match o.get(key) {
    Some(value) => @json.from_json(value)
    None => raise Invalid("VTK sidecar missing " + key)
  }
}

///|
fn vr_int(value : Json) -> Int raise {
  let number : Double = @json.from_json(value)
  if !finite(number) ||
    number < -2147483648.0 ||
    number > 2147483647.0 ||
    number != number.floor() {
    bad("VTK sidecar requires exact signed32 integers")
  }
  number.to_int()
}

///|
fn vr_ints(o : Map[String, Json], key : String) -> Array[Int] raise {
  let items : Array[Json] = vr_get(o, key)
  items.map(vr_int)
}

///|
fn vr_expect(c : Cursor, expected : String) -> Unit raise {
  if c.word() != expected {
    bad("VTK readback expected " + expected)
  }
}

///|
fn vr_count(c : Cursor) -> Int raise {
  let n = c.ai()
  if n < 0 || n > 1000000 {
    bad("VTK point/cell count outside stored mesh budget")
  }
  n
}

///|
/// Read only the existing legacy ASCII vtk_fields layout. Geometry tokens are
/// consumed for framing/index bounds, never converted, repaired or integrated.
/// Metadata coherence does not prove the sidecar came from an authentic source.
pub fn read_vtk_fields(data : Bytes, audit : Json) -> VtkFieldsReadback raise {
  if data.length() > 134217728 {
    bad("VTK readback exceeds 128 MiB")
  }
  let o = vr_object(audit)
  let version : String = vr_get(o, "source_version")
  if version != "2.2" && version != "4.1" {
    bad("VTK sidecar source version must be 2.2 or 4.1")
  }
  let rows : Array[Json] = vr_get(o, "fields")
  if rows.is_empty() || rows.length() > 1024 {
    bad("VTK readback requires 1..1024 selected fields")
  }
  let indices : Map[Int, Bool] = Map([])
  let plans : Array[VtkReadPlan] = []
  for row in rows {
    let item = vr_object(row)
    let actual : Json = vr_get(item, "field")
    let meta = vr_object(actual)
    let index = vr_int(vr_get(meta, "field_index"))
    let location : String = vr_get(meta, "location")
    let strings : Array[String] = vr_get(item, "strings")
    let reals : Array[Double] = vr_get(item, "reals")
    let integers = vr_ints(item, "integers")
    let array_name : String = vr_get(item, "value_array")
    if index < 0 || index >= 1024 || indices.contains(index) {
      bad("VTK sidecar has invalid/duplicate source index")
    }
    if strings.is_empty() || integers.length() < 3 || !reals.all(finite) {
      bad("VTK sidecar has invalid raw headers")
    }
    if (location != "NodeData" && location != "ElementData") ||
      ![1, 3, 9].contains(integers[1]) ||
      integers[2] < 0 ||
      array_name != "gmsh_value_\{index}" {
      bad("VTK sidecar field association/components/alias is inconsistent")
    }
    let frame : FieldFrame = {
      field_index: index,
      name: strings[0],
      location,
      components: integers[1],
      time_step: integers[0],
      time: if reals.is_empty() {
        None
      } else {
        Some(reals[0])
      },
      entries: integers[2],
      interpolation_scheme: if strings.length() > 1 && !strings[1].is_empty() {
        Some(strings[1])
      } else {
        None
      },
      partition: if integers.length() > 3 {
        Some(integers[3])
      } else {
        None
      },
    }
    if actual != frame.to_json() {
      bad("VTK sidecar frame does not match its raw headers")
    }
    indices[index] = true
    plans.push({ frame, array_name, })
  }
  let omitted = vr_ints(o, "omitted_field_indices")
  let mut previous = -1
  for index in omitted {
    if index <= previous || index >= 1024 || indices.contains(index) {
      bad("VTK sidecar omitted indices are inconsistent")
    }
    indices[index] = true
    previous = index
  }
  for index in 0..<indices.length() {
    if !indices.contains(index) {
      bad("VTK sidecar source-index coverage has a gap")
    }
  }
  let losses : Array[String] = vr_get(o, "losses")
  if !losses.contains("msh_field_headers_not_in_vtk") ||
    losses.contains("other_field_sections_omitted") != !omitted.is_empty() {
    bad("VTK sidecar field-omission losses are inconsistent")
  }
  let c : Cursor = { data, p: 0, binary: false, little: true, width: 8, }
  if c.line() != "# vtk DataFile Version 3.0" {
    bad("VTK readback requires legacy version 3.0")
  }
  let _ = c.line() // title is descriptive, not an identity or trust anchor
  if c.line() != "ASCII" {
    bad("VTK readback requires ASCII")
  }
  vr_expect(c, "DATASET")
  vr_expect(c, "UNSTRUCTURED_GRID")
  vr_expect(c, "POINTS")
  let points = vr_count(c)
  vr_expect(c, "double")
  for _ in 0..<(points * 3) {
    let _ = c.ar()
  }
  vr_expect(c, "CELLS")
  let cells = vr_count(c)
  let size = c.ai()
  if size < cells || size > data.length() {
    bad("VTK connectivity size is inconsistent")
  }
  let mut used = 0
  for _ in 0..<cells {
    let n = c.ai()
    if n < 1 || n > size - used - 1 {
      bad("VTK cell framing is inconsistent")
    }
    used = used + n + 1
    for _ in 0..<n {
      let index = c.ai()
      if index < 0 || index >= points {
        bad("VTK connectivity index is outside POINTS")
      }
    }
  }
  if used != size {
    bad("VTK connectivity size does not match cells")
  }
  vr_expect(c, "CELL_TYPES")
  if c.ai() != cells {
    bad("VTK cell type count mismatch")
  }
  for _ in 0..<cells {
    if c.ai() < 1 {
      bad("VTK cell type must be positive")
    }
  }
  let has_point = plans.any(p => p.frame.location == "NodeData")
  let has_cell = plans.any(p => p.frame.location == "ElementData")
  let other = (!has_point && points > 0) || (!has_cell && cells > 0)
  if losses.contains("other_association_tags_not_in_vtk") != other {
    bad("VTK sidecar association-tag loss is inconsistent")
  }
  let values : Map[Int, Array[Array[Double]]] = Map([])
  let point_tags : Array[Int] = []
  let cell_tags : Array[Int] = []
  for nodal in [true, false] {
    let group = plans.filter(p => (p.frame.location == "NodeData") == nodal)
    if group.is_empty() {
      continue
    }
    let count = if nodal { points } else { cells }
    vr_expect(c, if nodal { "POINT_DATA" } else { "CELL_DATA" })
    if c.ai() != count {
      bad("VTK association tuple count mismatch")
    }
    vr_expect(c, "FIELD")
    vr_expect(c, "FieldData")
    if c.ai() != group.length() + 1 {
      bad("VTK field array count mismatch")
    }
    for plan in group {
      vr_expect(c, plan.array_name)
      if c.ai() != plan.frame.components ||
        c.ai() != count ||
        plan.frame.entries != count {
        bad("VTK field components/coverage mismatch with sidecar")
      }
      vr_expect(c, "double")
      let tuples : Array[Array[Double]] = []
      for _ in 0..<count {
        let tuple = []
        for _ in 0..<plan.frame.components {
          tuple.push(c.ar())
        }
        tuples.push(tuple)
      }
      values[plan.frame.field_index] = tuples
    }
    vr_expect(c, "gmsh_tag")
    if c.ai() != 1 || c.ai() != count {
      bad("VTK original-tag array shape mismatch")
    }
    vr_expect(c, "int")
    let seen : Map[Int, Bool] = Map([])
    let tags = if nodal { point_tags } else { cell_tags }
    for _ in 0..<count {
      let tag = c.ai()
      if tag < 1 || seen.contains(tag) {
        bad("VTK original tags must be positive and unique per association")
      }
      seen[tag] = true
      tags.push(tag)
    }
  }
  while c.p < data.length() && white(data[c.p]) {
    c.p = c.p + 1
  }
  if c.p != data.length() {
    bad("VTK readback has unexpected trailing data")
  }
  {
    points,
    cells,
    has_point_tags: has_point,
    has_cell_tags: has_cell,
    point_tags,
    cell_tags,
    fields: plans.map(p => {
      field: p.frame,
      value_array: p.array_name,
      values: values[p.frame.field_index],
    }),
    source_version: version,
    omitted_field_indices: omitted,
    losses,
  }
}
