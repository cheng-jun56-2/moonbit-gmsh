///|
pub(all) struct BoundaryGroup {
  tag : Int
  facets : Int
} derive(ToJson)

///|
pub extend BoundaryGroup with ToJson::{to_json}

///|
/// A label inventory, not a finite-element boundary-condition certificate.
/// Physical tags are scoped to boundary_dimension. Volume labels never count.
pub(all) struct BoundaryCoverage {
  boundary_dimension : Int
  facets : Int
  groups : Array[BoundaryGroup]
  unlabeled : Array[BoundarySource]
  multiple : Array[BoundarySource]
  missing_groups : Array[Int]
} derive(ToJson)

///|
pub extend BoundaryCoverage with ToJson::{to_json}

///|
/// required_groups is a caller-supplied contract, not inferred from group names.
/// Multiple labels can be intentional; consumers choose whether to reject them.
/// Inspection does not authorize the separate lossy derived-mesh export.
pub fn Boundary::coverage(
  self : Boundary,
  required_groups? : Array[Int] = [],
) -> BoundaryCoverage raise {
  if required_groups.length() > 100000 {
    bad("required_groups exceeds 100000")
  }
  let required : Map[Int, Bool] = Map([])
  for tag in required_groups {
    if tag <= 0 || required.contains(tag) {
      bad("required_groups must contain distinct positive tags")
    }
    required[tag] = true
  }
  let counts : Map[Int, Int] = Map([])
  let unlabeled : Array[BoundarySource] = []
  let multiple : Array[BoundarySource] = []
  for i, element in self.output.es {
    if element.physical.is_empty() {
      unlabeled.push(self.summary.facets[i])
    }
    if element.physical.length() > 1 {
      multiple.push(self.summary.facets[i])
    }
    for tag in element.physical {
      counts[tag] = counts.get(tag).unwrap_or(0) + 1
    }
  }
  let tags = counts.keys().to_array()
  tags.sort()
  let missing = required_groups.filter(tag => !counts.contains(tag))
  missing.sort()
  {
    boundary_dimension: self.summary.boundary_dimension,
    facets: self.output.es.length(),
    groups: tags.map(tag => { tag, facets: counts[tag], }),
    unlabeled,
    multiple,
    missing_groups: missing,
  }
}
