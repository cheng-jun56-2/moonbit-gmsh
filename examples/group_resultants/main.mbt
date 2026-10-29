///|
fn source_mesh() -> @gmsh.Mesh raise {
  let text =
    #|$MeshFormat
    #|4.1 0 8
    #|$EndMeshFormat
    #|$PhysicalNames
    #|4
    #|2 44 "受载甲"
    #|2 55 "opposed"
    #|2 66 "vertical"
    #|1 44 "edge same id"
    #|$EndPhysicalNames
    #|$Entities
    #|0 1 3 0
    #|3 0.0 0.0 0.0 2.0 0.0 0.0 1 44 0
    #|7 0.0 0.0 0.0 2.0 2.0 0.0 2 44 55 0
    #|8 0.0 0.0 0.0 0.0 2.0 3.0 2 44 66 0
    #|9 0.0 0.0 0.0 2.0 2.0 0.0 1 55 0
    #|$EndEntities
    #|$Nodes
    #|1 5 10 2147483647
    #|2 7 1 5
    #|50
    #|2147483647
    #|70
    #|10
    #|90
    #|0.0 2.0 0.0 0.0 1.0
    #|9.0 9.0 9.0 9.0 9.0
    #|0.0 0.0 3.0 0.0 3.0
    #|2.0 0.0 0.0 1.0 0.0
    #|0.0 0.0 0.0 0.0 0.0
    #|$EndNodes
    #|$Elements
    #|4 4 8 1000
    #|2 8 2 1
    #|8 90 50 70
    #|1 3 1 1
    #|1000 90 10
    #|2 7 2 1
    #|700 90 10 50
    #|2 9 2 1
    #|201 90 50 10
    #|$EndElements
    #|$ElementData
    #|3
    #|"stress"
    #|"named-descriptor"
    #|"other-field"
    #|0
    #|5
    #|2
    #|9
    #|3
    #|0
    #|90
    #|700 1.0 2.0 3.0 4.0 5.0 6.0 7.0 8.0 9.0
    #|8 9.0 8.0 7.0 6.0 5.0 4.0 3.0 2.0 1.0
    #|201 0.5 0.5 0.5 0.5 0.5 0.5 0.5 0.5 0.5
    #|$EndElementData
    #|$NodeData
    #|3
    #|"压力"
    #|""
    #|"source-extra"
    #|2
    #|0.25
    #|9.25
    #|5
    #|7
    #|1
    #|5
    #|31
    #|91
    #|2147483647 9.0
    #|10 3.0
    #|70 1.0
    #|50 1.0
    #|90 1.0
    #|$EndNodeData
    #|$NodeData
    #|2
    #|"压力"
    #|""
    #|1
    #|0.25
    #|4
    #|7
    #|1
    #|3
    #|0
    #|90 10.0
    #|50 10.0
    #|70 10.0
    #|$EndNodeData
    #|$ElementData
    #|1
    #|"face scalar"
    #|0
    #|3
    #|9
    #|1
    #|3
    #|700 2.0
    #|8 -1.0
    #|201 2.0
    #|$EndElementData
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
/// Public-package composition with complete receiving witnesses. Self-authored,
/// not customer adoption or a new integration rule. Groups may overlap.
fn main raise {
  let source = source_mesh()
  let original = snapshot(source)
  let groups = [55, 44]
  let receipts = groups.map(group => {
    let selected = source.select_physical(2, group)
    let received = @gmsh.decode(selected.encode(binary=true))
    let estimate = received.integrate_surface_normal_field(1, max_samples=12)
    let receipt : Json = {
      "physical_group": group.to_json(),
      "mesh": snapshot(received),
      "estimate": estimate.to_json(),
    }
    receipt
  })
  guard snapshot(source) == original else {
    raise Failure("group receiving mutated the source")
  }
  let result : Json = {
    "evidence": "self-authored public-package composition",
    "field_index": 1,
    "groups": receipts.to_json(),
    "source_unchanged": true,
    "group_aggregate_provided": false,
  }
  println(result.stringify())
}
