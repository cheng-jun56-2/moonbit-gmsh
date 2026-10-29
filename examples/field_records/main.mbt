///|
fn source_mesh() -> @gmsh.Mesh raise {
  let text =
    #|$MeshFormat
    #|4.1 0 8
    #|$EndMeshFormat
    #|$PhysicalNames
    #|3
    #|0 9 "point"
    #|1 8 "edge"
    #|2 44 "原表面"
    #|$EndPhysicalNames
    #|$Entities
    #|1 1 1 0
    #|1 1.0 0.0 0.0 1 9
    #|3 0.0 0.0 0.0 1.0 0.0 0.0 1 8 0
    #|7 0.0 0.0 0.0 3.0 3.0 9.0 1 44 0
    #|$EndEntities
    #|$Nodes
    #|1 4 7 2147483647
    #|2 7 1 4
    #|50
    #|7
    #|90
    #|2147483647
    #|0.0 3.0 0.0 0.0 1.0
    #|1.0 0.0 0.0 1.0 0.0
    #|0.0 0.0 0.0 0.0 0.0
    #|9.0 9.0 9.0 9.0 9.0
    #|$EndNodes
    #|$Elements
    #|3 3 3 700
    #|0 1 15 1
    #|7 7
    #|1 3 1 1
    #|3 90 7
    #|2 7 2 1
    #|700 90 7 50
    #|$EndElements
    #|$NodeData
    #|3
    #|"温度"
    #|""
    #|"first-extra"
    #|2
    #|0.5
    #|7.25
    #|5
    #|8
    #|1
    #|2
    #|31
    #|90
    #|50 30.0
    #|7 10.0
    #|$EndNodeData
    #|$ElementData
    #|3
    #|"温度"
    #|"named-rule"
    #|"cell-extra"
    #|1
    #|0.5
    #|5
    #|8
    #|9
    #|2
    #|0
    #|91
    #|7 9.0 8.0 7.0 6.0 5.0 4.0 3.0 2.0 1.0
    #|700 1.0 2.0 3.0 4.0 5.0 6.0 7.0 8.0 9.0
    #|$EndElementData
    #|$NodeData
    #|1
    #|"velocity"
    #|0
    #|3
    #|2
    #|3
    #|1
    #|7 1.0 2.0 3.0
    #|$EndNodeData
    #|$NodeData
    #|3
    #|"温度"
    #|""
    #|"later"
    #|1
    #|0.25
    #|5
    #|4
    #|1
    #|2
    #|22
    #|92
    #|7 15.0
    #|90 40.0
    #|$EndNodeData
    #|$NodeData
    #|3
    #|"温度"
    #|"named-scheme"
    #|"raw-only"
    #|1
    #|0.5
    #|5
    #|8
    #|1
    #|1
    #|31
    #|93
    #|7 20.0
    #|$EndNodeData
    #|$ElementData
    #|3
    #|"温度"
    #|""
    #|"raw-cell"
    #|1
    #|0.25
    #|3
    #|4
    #|1
    #|1
    #|700 -2.0
    #|$EndElementData
    #|$NodeData
    #|1
    #|"empty"
    #|0
    #|3
    #|0
    #|1
    #|0
    #|$EndNodeData
    #|$ElementData
    #|1
    #|"vector"
    #|0
    #|3
    #|3
    #|3
    #|1
    #|7 4.0 5.0 6.0
    #|$EndElementData
    #|$Opaque
    #|same-source-field-indices
    #|$EndOpaque
    #|
  @gmsh.decode(@utf8.encode(text))
}

///|
fn snapshot(mesh : @gmsh.Mesh) -> Json {
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
/// Complete self-authored public-package receiver. Read raw rows, not a time
/// interpolation/physical/source certificate. Opaque source context stays intact.
fn main raise {
  let source = source_mesh()
  let before = snapshot(source)
  let indices = [4, 0, 3, 2]
  let node = source.field_records("NodeData", 7, indices)
  let cell = source.field_records("ElementData", 700, [5, 1])
  let collision = source.field_records("ElementData", 7, [7, 1])
  let original = node.to_json()
  let changed = source.field_records("NodeData", 7, indices)
  changed.nodes[0].xyz[0] = 99.0
  changed.nodes[0].parameters[0] = 99.0
  changed.records[0].strings[0] = "changed"
  changed.records[0].reals[0] = 99.0
  changed.records[0].integers[0] = 99
  changed.records[0].values[0] = 99.0
  changed.unknown_section_names[0] = "changed"
  indices[0] = 0
  guard source.field_records("NodeData", 7, [4, 0, 3, 2]).to_json() == original &&
    node.to_json() == original &&
    snapshot(source) == before else {
    raise Failure("field record receiver ownership/source differs")
  }
  let received : Json = {
    "evidence": "self-authored public-package raw record receiver",
    "node": node.to_json(),
    "cell": cell.to_json(),
    "collision": collision.to_json(),
    "source_unchanged": true,
    "ownership_isolated": true,
    "time_series_certified": false,
  }
  println(received.stringify())
}
