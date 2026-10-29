///|
/// A node-only snapshot, not an induced-cell subset or interpolation. Tags
/// refer to the original node domain, including isolated nodes; API node order
/// follows the unique request. No vertex cells or cell-to-node values are made.
pub fn Mesh::node_cloud(self : Mesh, tags : Array[Int]) -> Mesh raise {
  if !self.unknown.is_empty() {
    bad("node cloud requires explicit removal of opaque sections")
  }
  if tags.length() > 1000000 {
    bad("node cloud request exceeds limit")
  }
  let selected : Map[Int, Bool] = Map([])
  let nodes : Array[Node] = []
  for tag in tags {
    if selected.contains(tag) {
      bad("duplicate requested node")
    }
    let index = match self.ni.get(tag) {
      Some(index) => index
      None => raise Invalid("unknown requested node \{tag}")
    }
    selected[tag] = true
    nodes.push(self.ns[index])
  }
  let fields = self.fs.map(f => {
    // Node and cell tags are separate domains, even when numerically equal.
    // Preserve raw section positions/heads, emptying every ElementData view.
    let entries = if f.location == "NodeData" {
      f.entries.filter(d => selected.contains(d.tag))
    } else {
      []
    }
    let integers = f.integers.copy()
    integers[2] = entries.length()
    { ..f, entries, integers, }
  })
  mesh(
    nodes,
    [],
    entities=self.ents,
    names=self.names,
    fields~,
    version=self.version,
  )
}
