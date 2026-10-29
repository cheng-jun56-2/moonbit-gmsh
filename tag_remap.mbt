///|
/// One prescribed ID change in either the original node or element domain.
/// Both domains require complete maps; the same numeric IDs may occur in each.
pub(all) struct TagMapping {
  old_tag : Int
  new_tag : Int
} derive(ToJson)

///|
pub extend TagMapping with ToJson::{to_json}

///|
fn tag_remap_plan(
  request : Array[TagMapping],
  known : Map[Int, Int],
  count : Int,
  domain : String,
) -> Map[Int, Int] raise MeshError {
  if request.length() != count {
    bad("\{domain} map must cover the complete original domain")
  }
  let mapping : Map[Int, Int] = Map([])
  let used : Map[Int, Bool] = Map([])
  for row in request {
    if !known.contains(row.old_tag) {
      bad("unknown original \{domain} tag \{row.old_tag}")
    }
    if mapping.contains(row.old_tag) {
      bad("duplicate original \{domain} tag")
    }
    positive(row.new_tag, domain)
    if used.contains(row.new_tag) {
      bad("duplicate destination \{domain} tag")
    }
    mapping[row.old_tag] = row.new_tag
    used[row.new_tag] = true
  }
  mapping
}

///|
/// Simultaneous complete one-to-one tag changes, not optimized numbering,
/// selection or welding. Source order, geometry, semantic IDs and raw heads
/// stay; only object/connectivity/associated field-row tags change.
pub fn Mesh::remap_tags(
  self : Mesh,
  node_tags : Array[TagMapping],
  element_tags : Array[TagMapping],
) -> Mesh raise MeshError {
  if !self.unknown.is_empty() {
    bad("tag remapping requires explicit removal of opaque sections")
  }
  // Validate both original domains before constructing output. Destinations
  // may also be old IDs: looking up only original tags permits swaps/cycles.
  let nm = tag_remap_plan(node_tags, self.ni, self.ns.length(), "node")
  let em = tag_remap_plan(element_tags, self.ei, self.es.length(), "element")
  let ns = self.ns.map(n => { ..n, tag: nm[n.tag], })
  let es = self.es.map(e => {
    ..e,
    tag: em[e.tag],
    nodes: e.nodes.map(t => nm[t]),
  })
  let fs = self.fs.map(f => {
    ..f,
    entries: f.entries.map(d => {
      ..d,
      tag: if f.location == "NodeData" {
        nm[d.tag]
      } else {
        em[d.tag]
      },
    }),
  })
  mesh(
    ns,
    es,
    entities=self.ents,
    names=self.names,
    fields=fs,
    version=self.version,
  )
}
