///|
/// Copy exact field sections in the requested unique, zero-based source order.
/// [] removes all known fields; a retained empty section is still a field.
/// Geometry, tags, metadata and raw selected headers (including time steps)
/// remain unchanged. Output field position i refers to field_indices[i].
pub fn Mesh::select_fields(
  self : Mesh,
  field_indices : Array[Int],
) -> Mesh raise {
  if field_indices.length() > 1024 {
    bad("field selection request exceeds 1024 sections")
  }
  let seen : Map[Int, Bool] = Map([])
  let selected : Array[Field] = []
  let mut identity = field_indices.length() == self.fs.length()
  for position, index in field_indices {
    if index < 0 || index >= self.fs.length() {
      bad("field selection index is out of range")
    }
    if seen.contains(index) {
      bad("duplicate requested field index")
    }
    seen[index] = true
    identity = identity && position == index
    selected.push(self.fs[index])
  }
  // Opaque sections may refer to field positions. A validated identity keeps
  // their context; removal/reordering needs the existing explicit loss gate.
  if !identity && !self.unknown.is_empty() {
    bad("field selection requires explicit removal of opaque sections")
  }
  mesh(
    self.ns,
    self.es,
    entities=self.ents,
    names=self.names,
    fields=selected,
    unknown=self.unknown,
    version=self.version,
  )
}
