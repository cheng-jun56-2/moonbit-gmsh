///|
/// One original field section, indexed exactly as Mesh::fields. Same names,
/// steps and partitions are not combined. No field values are copied here.
pub(all) struct FieldFrame {
  field_index : Int
  name : String
  location : String
  components : Int
  time_step : Int
  time : Double?
  entries : Int
  interpolation_scheme : String?
  partition : Int?
} derive(ToJson)

///|
pub extend FieldFrame with ToJson::{to_json}

///|
fn field_frame_info(f : Field, field_index : Int) -> FieldFrame {
  {
    field_index,
    name: f.strings[0],
    location: f.location,
    components: f.integers[1],
    time_step: f.integers[0],
    time: if f.reals.is_empty() {
      None
    } else {
      Some(f.reals[0])
    },
    entries: f.entries.length(),
    interpolation_scheme: if f.strings.length() > 1 && !f.strings[1].is_empty() {
      Some(f.strings[1])
    } else {
      None
    },
    partition: if f.integers.length() > 3 {
      Some(f.integers[3])
    } else {
      None
    },
  }
}

///|
/// Lightweight frame metadata in input order. This is a catalog, not a field
/// selection rule, interpolation-scheme implementation or partition merger.
pub fn Mesh::field_frames(self : Mesh) -> Array[FieldFrame] {
  self.fs.mapi((i, f) => field_frame_info(f, i))
}

///|
/// Tag presence only: complete coverage does not certify geometry, numeric
/// range, vector components, supported interpolation or outward orientation.
/// Missing tags are current IDs and may change after Mesh::compact.
pub(all) struct SurfaceFieldCoverage {
  field : FieldFrame
  elements : Int
  skipped_lower_dimension : Int
  required_tags : Int
  present_tags : Int
  missing_count : Int
  missing_tags : Array[Int]
  missing_truncated : Bool
  all_required_tags_present : Bool
} derive(ToJson)

///|
pub extend SurfaceFieldCoverage with ToJson::{to_json}

///|
/// Inspect one exact frame on an explicitly selected 2D mesh, without geometry
/// evaluation or missing-value filling. NodeData requires every unique full
/// surface node (including quadratic roles); ElementData requires every face.
/// Lower-dimensional cells/isolated nodes do not add requirements. Missing IDs
/// follow first use in current element/connectivity order; only this list is
/// capped, while counts always cover the full selected mesh.
pub fn Mesh::surface_field_coverage(
  self : Mesh,
  field_index : Int,
  max_missing? : Int = 1000,
) -> SurfaceFieldCoverage raise {
  if field_index < 0 || field_index >= self.fs.length() {
    bad("surface field coverage field_index is out of range")
  }
  if max_missing < 0 || max_missing > 100000 {
    bad("surface field coverage max_missing must be 0..100000")
  }
  let mut dimension = -1
  let mut elements = 0
  for e in self.es {
    let dim = element_shape(e.kind).0
    dimension = dimension.max(dim)
    if dim == 2 {
      elements += 1
    }
  }
  if dimension != 2 {
    bad(
      "surface field coverage requires a 2D mesh; explicitly extract/select the boundary first",
    )
  }
  let f = self.fs[field_index]
  let available : Map[Int, Bool] = Map([])
  for d in f.entries {
    available[d.tag] = true
  }
  let required : Map[Int, Bool] = Map([])
  let missing_tags : Array[Int] = []
  let mut required_tags = 0
  let mut missing_count = 0
  for e in self.es {
    if element_shape(e.kind).0 != 2 {
      continue
    }
    let tags = if f.location == "NodeData" { e.nodes } else { [e.tag] }
    for tag in tags {
      if required.contains(tag) {
        continue
      }
      required[tag] = true
      required_tags += 1
      if !available.contains(tag) {
        missing_count += 1
        if missing_tags.length() < max_missing {
          missing_tags.push(tag)
        }
      }
    }
  }
  {
    field: field_frame_info(f, field_index),
    elements,
    skipped_lower_dimension: self.es.length() - elements,
    required_tags,
    present_tags: required_tags - missing_count,
    missing_count,
    missing_tags,
    missing_truncated: missing_count > missing_tags.length(),
    all_required_tags_present: missing_count == 0,
  }
}
