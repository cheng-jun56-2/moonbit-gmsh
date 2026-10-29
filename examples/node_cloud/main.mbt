///|
fn pc_source() -> @gmsh.Mesh raise {
  let text =
    #|$MeshFormat
    #|4.1 0 8
    #|$EndMeshFormat
    #|$PhysicalNames
    #|2
    #|0 9 "point marker"
    #|2 44 "original surface"
    #|$EndPhysicalNames
    #|$Entities
    #|1 0 1 0
    #|1 0 0 0 1 9
    #|7 0 0 0 9 9 9 1 44 0
    #|$EndEntities
    #|$Nodes
    #|2 4 7 2147483647
    #|2 7 1 3
    #|50
    #|2147483647
    #|7
    #|0 3 0 0 1
    #|9 9 9 9 9
    #|2 0 0 1 0
    #|0 1 0 1
    #|90
    #|0 0 0
    #|$EndNodes
    #|$Elements
    #|2 2 7 700
    #|0 1 15 1
    #|7 90
    #|2 7 2 1
    #|700 90 7 50
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
    #|4
    #|31
    #|90
    #|7 20
    #|50 30
    #|2147483647 99
    #|90 10
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
    #|4
    #|90 0 0 0
    #|2147483647 9 8 7
    #|50 3 2 1
    #|7 2 1 0
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
fn pc_snapshot(mesh : @gmsh.Mesh) -> Json {
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
/// Self-authored public node-domain receiving; no interpolation/adoption claim.
fn main raise {
  let source = pc_source()
  let before = pc_snapshot(source)
  let tags = [2147483647, 7, 50]
  let pc_result = source.node_cloud(tags)
  let received = pc_snapshot(pc_result)
  let fields = pc_result.fields()
  fields[0].entries[0].values[0] = 999.0
  let nodes = pc_result.nodes()
  nodes[0].parameters[0] = 999.0
  tags[0] = 90
  guard pc_snapshot(source) == before && pc_snapshot(pc_result) == received else {
    raise Failure("node cloud receiver ownership differs")
  }
  let result : Json = {
    "evidence": "self-authored node-only Mesh public receiver",
    "selected": received,
    "single": pc_snapshot(source.node_cloud([7])),
    "empty": pc_snapshot(source.node_cloud([])),
    "all": pc_snapshot(source.node_cloud([90, 2147483647, 7, 50])),
    "source_unchanged": true,
    "ownership_isolated": true,
  }
  println(result.stringify())
}
