///|
/// Resolve one exact declared name in an explicit dimension, then use the
/// existing field-preserving numeric selection. Names are labels, not unique
/// global identities: never pick the first or prefer a populated duplicate.
pub fn Mesh::select_physical_name(
  self : Mesh,
  dimension : Int,
  name : String,
) -> Mesh raise {
  if dimension < 0 || dimension > 3 {
    bad("physical name selection requires dimension0..3")
  }
  let mut matched : Int? = None
  for label in self.names {
    if label.dim == dimension && label.name == name {
      if matched is Some(_) {
        bad("physical name is ambiguous in the requested dimension")
      }
      matched = Some(label.tag)
    }
  }
  let group = match matched {
    Some(tag) => tag
    None =>
      raise Invalid("physical name is not declared in the requested dimension")
  }
  // This retains declared-but-empty subsets and the established opaque/loss,
  // original-order, raw-header filtering and owned Mesh contracts unchanged.
  self.select_physical(dimension, group)
}
