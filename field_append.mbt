///|
/// Append exact donor sections only after checking the complete discrete mesh
/// identity by original tags, numeric xyz and ordered connectivity roles.
/// Storage order/context labels may differ; recipient context stays authoritative.
/// This is no interpolation, unit/physical equivalence or source certificate.
pub fn Mesh::append_fields(
  self : Mesh,
  donor : Mesh,
  field_indices : Array[Int],
) -> Mesh raise MeshError {
  if field_indices.is_empty() ||
    field_indices.length() > 1024 ||
    self.fs.length() + field_indices.length() > 1024 {
    bad(
      "field append requires1..1024 sections within the combined model budget",
    )
  }
  let seen : Map[Int, Bool] = Map([])
  for index in field_indices {
    if index < 0 || index >= donor.fs.length() || seen.contains(index) {
      bad("field append has an invalid/duplicate donor section index")
    }
    seen[index] = true
  }
  // Opaque sections can refer to frame positions or donor-specific context.
  // Explicit without_unknown on both inputs is the existing loss authorization.
  if !self.unknown.is_empty() || !donor.unknown.is_empty() {
    bad("field append requires explicit removal of both opaque contexts")
  }
  if self.ns.length() != donor.ns.length() ||
    self.es.length() != donor.es.length() {
    bad("field append node/element tag domains differ")
  }
  for node in donor.ns {
    let original = match self.ni.get(node.tag) {
      Some(index) => self.ns[index]
      None => raise Invalid("field append unknown node tag \{node.tag}")
    }
    if original.xyz != node.xyz {
      bad("field append coordinates differ at node tag \{node.tag}")
    }
  }
  for element in donor.es {
    let original = match self.ei.get(element.tag) {
      Some(index) => self.es[index]
      None => raise Invalid("field append unknown element tag \{element.tag}")
    }
    if original.kind != element.kind || original.nodes != element.nodes {
      bad(
        "field append type/ordered roles differ at element tag \{element.tag}",
      )
    }
  }
  let fields = self.fs.copy()
  for index in field_indices {
    fields.push(donor.fs[index])
  }
  // The existing constructor deep-copies all heads/data/context and enforces
  // combined value/count budgets before returning a complete owned Mesh.
  mesh(
    self.ns,
    self.es,
    entities=self.ents,
    names=self.names,
    fields~,
    version=self.version,
  )
}
