///|
/// One exact original datum, with the original complete section headers.
/// Sections may have different names/times/components: no series is inferred.
pub(all) struct FieldRecord {
  field : FieldFrame
  strings : Array[String]
  reals : Array[Double]
  integers : Array[Int]
  values : Array[Double]
} derive(ToJson)

///|
pub extend FieldRecord with ToJson::{to_json}

///|
/// Owned raw observations at an explicit same-source association/tag.
/// NodeData has one node and no element; ElementData has every ordered node
/// role and the original element. This witness is not full mesh certification.
pub(all) struct FieldRecords {
  source_version : String
  location : String
  tag : Int
  nodes : Array[Node]
  element : Element?
  records : Array[FieldRecord]
  unknown_section_names : Array[String]
} derive(ToJson)

///|
pub extend FieldRecords with ToJson::{to_json}

///|
/// Read1..1024 unique original sections in the requested order. Each must have
/// this association and contain the original tag. Missing rows fail the whole
/// query, without fill/partial results. Raw named schemes and opaque context
/// need no interpretation/removal because neither mesh nor section order changes.
pub fn Mesh::field_records(
  self : Mesh,
  location : String,
  tag : Int,
  field_indices : Array[Int],
) -> FieldRecords raise MeshError {
  if location != "NodeData" && location != "ElementData" {
    bad("field records require NodeData or ElementData association")
  }
  if field_indices.is_empty() || field_indices.length() > 1024 {
    bad("field records require1..1024 original sections")
  }
  let seen : Map[Int, Bool] = Map([])
  for index in field_indices {
    if index < 0 || index >= self.fs.length() || seen.contains(index) {
      bad("field records have an invalid/duplicate section index")
    }
    seen[index] = true
    if self.fs[index].location != location {
      bad("field records association differs at section \{index}")
    }
  }
  let element = if location == "ElementData" {
    match self.ei.get(tag) {
      Some(index) => Some(copy_element(self.es[index]))
      None => raise Invalid("field records unknown element tag \{tag}")
    }
  } else {
    None
  }
  let nodes = match element {
    Some(e) => e.nodes.map(t => copy_node(self.ns[self.ni[t]]))
    None =>
      match self.ni.get(tag) {
        Some(index) => [copy_node(self.ns[index])]
        None => raise Invalid("field records unknown node tag \{tag}")
      }
  }
  let records = field_indices.map(index => {
    let f = self.fs[index]
    let mut values : Array[Double]? = None
    // Unique section indices bound total scanned rows by the existing Mesh
    // field-data budget. Do not build a full cloned field/dump for one tag.
    for datum in f.entries {
      if datum.tag == tag {
        values = Some(datum.values.copy())
        break
      }
    }
    let values = match values {
      Some(value) => value
      None =>
        raise Invalid("field records missing tag \{tag} in section \{index}")
    }
    FieldRecord::{
      field: field_frame_info(f, index),
      strings: f.strings.copy(),
      reals: f.reals.copy(),
      integers: f.integers.copy(),
      values,
    }
  })
  {
    source_version: self.version,
    location,
    tag,
    nodes,
    element,
    records,
    unknown_section_names: self.unknown.map(s => s.name),
  }
}
