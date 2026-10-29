///|
fn rt_source() -> @gmsh.Mesh raise {
  let text =
    #|$MeshFormat
    #|4.1 0 8
    #|$EndMeshFormat
    #|$PhysicalNames
    #|2
    #|1 9 "edge metadata"
    #|2 44 "surface metadata"
    #|$EndPhysicalNames
    #|$Entities
    #|0 1 1 0
    #|3 0 0 0 2 0 0.25 1 9 0
    #|7 0 0 0 9 9 9 1 44 0
    #|$EndEntities
    #|$Nodes
    #|1 7 7 2147483647
    #|2 7 1 7
    #|50
    #|2147483647
    #|7
    #|90
    #|100
    #|150
    #|200
    #|0 2 0 0 1
    #|9 9 9 9 9
    #|2 0 0 1 0
    #|0 0 0 0 0
    #|1 0 0.25 0.5 0
    #|1 1 0.5 0.5 0.5
    #|0 1 0 0 0.5
    #|$EndNodes
    #|$Elements
    #|2 2 7 700
    #|1 3 8 1
    #|7 90 7 100
    #|2 7 9 1
    #|700 90 7 50 100 150 200
    #|$EndElements
    #|$NodeData
    #|3
    #|"temperature"
    #|""
    #|"extra"
    #|2
    #|0.5
    #|7.25
    #|5
    #|8
    #|1
    #|7
    #|31
    #|90
    #|7 20
    #|50 30
    #|2147483647 99
    #|90 10
    #|100 12
    #|150 23
    #|200 13
    #|$EndNodeData
    #|$ElementData
    #|2
    #|"stress"
    #|"raw-cell"
    #|1
    #|0.5
    #|5
    #|8
    #|9
    #|2
    #|0
    #|92
    #|7 9 8 7 6 5 4 3 2 1
    #|700 1 2 3 4 5 6 7 8 9
    #|$EndElementData
    #|$NodeData
    #|1
    #|"velocity"
    #|0
    #|3
    #|3
    #|3
    #|7
    #|2147483647 9 8 7
    #|90 0 0 0
    #|200 0 1 0
    #|150 1 1 0.5
    #|100 1 0 0.25
    #|50 0 2 0
    #|7 2 0 0
    #|$EndNodeData
    #|$NodeData
    #|1
    #|"empty"
    #|0
    #|3
    #|7
    #|1
    #|0
    #|$EndNodeData
    #|$NodeData
    #|2
    #|"tensor"
    #|"raw-node-scheme"
    #|1
    #|0.25
    #|3
    #|4
    #|9
    #|3
    #|50 5 5 5 5 5 5 5 5 5
    #|2147483647 9 9 9 9 9 9 9 9 9
    #|7 7 7 7 7 7 7 7 7 7
    #|$EndNodeData
    #|
  @gmsh.decode(@utf8.encode(text))
}

///|
fn rt_snapshot(mesh : @gmsh.Mesh) -> Json {
  {
    "source_version": mesh.source_version().to_json(),
    "nodes": mesh.nodes().to_json(),
    "elements": mesh.elements().to_json(),
    "entities": mesh.entities().to_json(),
    "physical_names": mesh.physical_names().to_json(),
    "fields": mesh.fields().to_json(),
    "unknown_sections": mesh.unknown_sections().to_json(),
  }
}

///|
fn rt_node_maps() -> Array[@gmsh.TagMapping] {
  [
    { old_tag: 7, new_tag: 2147483647, },
    { old_tag: 150, new_tag: 50, },
    { old_tag: 90, new_tag: 3, },
    { old_tag: 2147483647, new_tag: 7, },
    { old_tag: 200, new_tag: 90, },
    { old_tag: 50, new_tag: 100, },
    { old_tag: 100, new_tag: 150, },
  ]
}

///|
fn rt_element_maps() -> Array[@gmsh.TagMapping] {
  [{ old_tag: 700, new_tag: 7, }, { old_tag: 7, new_tag: 700, }]
}

///|
fn main raise {
  let source = rt_source()
  let before = rt_snapshot(source)
  let node_tags = rt_node_maps()
  let element_tags = rt_element_maps()
  let mapped = source.remap_tags(node_tags, element_tags)
  let received = rt_snapshot(mapped)
  let nodes = mapped.nodes()
  let elements = mapped.elements()
  let fields = mapped.fields()
  let entities = mapped.entities()
  nodes[0].parameters[0] = 999.0
  elements[0].nodes[0] = 999
  fields[1].entries[0].values[0] = 999.0
  entities[0].bounds[0] = 999.0
  node_tags[0] = { old_tag: 7, new_tag: 999, }
  element_tags[0] = { old_tag: 700, new_tag: 999, }
  guard rt_snapshot(source) == before && rt_snapshot(mapped) == received else {
    raise Failure("tag remap receiver ownership differs")
  }
  let inverse_nodes = rt_node_maps().map(r => @gmsh.TagMapping::{
    old_tag: r.new_tag,
    new_tag: r.old_tag,
  })
  let inverse_elements = rt_element_maps().map(r => @gmsh.TagMapping::{
    old_tag: r.new_tag,
    new_tag: r.old_tag,
  })
  let identity_nodes = source
    .nodes()
    .map(n => @gmsh.TagMapping::{ old_tag: n.tag, new_tag: n.tag, })
  let identity_elements = source
    .elements()
    .map(e => @gmsh.TagMapping::{ old_tag: e.tag, new_tag: e.tag, })
  let empty = @gmsh.mesh([], [], version="4.1")
  let result : Json = {
    "evidence": "self-authored complete prescribed tag remap public receiver",
    "mapped": received,
    "identity": rt_snapshot(
      source.remap_tags(identity_nodes, identity_elements),
    ),
    "recovered": rt_snapshot(mapped.remap_tags(inverse_nodes, inverse_elements)),
    "empty": rt_snapshot(empty.remap_tags([], [])),
    "source_unchanged": true,
    "ownership_isolated": true,
  }
  println(result.stringify())
}
