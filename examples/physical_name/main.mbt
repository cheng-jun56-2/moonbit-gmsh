///|
fn pn_source() -> @gmsh.Mesh raise {
  let text =
    #|$MeshFormat
    #|4.1 0 8
    #|$EndMeshFormat
    #|$PhysicalNames
    #|5
    #|2 44 "热壁 面"
    #|1 9 "热壁 面"
    #|2 55 "outlet"
    #|2 88 "declared-only"
    #|0 5 ""
    #|$EndPhysicalNames
    #|$Entities
    #|0 1 3 0
    #|3 0 0 0 2 0 0 1 9 0
    #|7 0 0 0 9 9 9 1 44 0
    #|8 0 0 0 9 9 9 1 55 0
    #|9 0 0 0 0 0 0 1 88 0
    #|$EndEntities
    #|$Nodes
    #|1 4 7 2147483647
    #|2 7 1 4
    #|50
    #|2147483647
    #|7
    #|90
    #|0 3 0 0 1
    #|9 9 9 9 9
    #|2 0 0 1 0
    #|0 0 0 0 0
    #|$EndNodes
    #|$Elements
    #|3 3 3 700
    #|1 3 1 1
    #|3 90 7
    #|2 8 2 1
    #|8 7 2147483647 50
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
    #|2147483647 9
    #|7 20
    #|50 30
    #|90 10
    #|$EndNodeData
    #|$ElementData
    #|2
    #|"stress"
    #|"named-rule"
    #|0
    #|5
    #|2
    #|9
    #|2
    #|0
    #|92
    #|8 9 8 7 6 5 4 3 2 1
    #|700 1 2 3 4 5 6 7 8 9
    #|$EndElementData
    #|$NodeData
    #|1
    #|"isolated vector"
    #|0
    #|3
    #|3
    #|3
    #|1
    #|2147483647 9 8 7
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
    #|
  @gmsh.decode(@utf8.encode(text))
}

///|
fn pn_snapshot(mesh : @gmsh.Mesh) -> Json {
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
/// Self-authored complete public receiver, not external adoption.
fn main raise {
  let source = pn_source()
  let before = pn_snapshot(source)
  let wall = source.select_physical_name(2, "热壁 面")
  let line = source.select_physical_name(1, "热壁 面")
  let outlet = source.select_physical_name(2, "outlet")
  let declared = source.select_physical_name(2, "declared-only")
  let empty_name = source.select_physical_name(0, "")
  let original = pn_snapshot(wall)
  let fields = wall.fields()
  fields[0].entries[0].values[0] = 999.0
  let nodes = wall.nodes()
  nodes[0].parameters[0] = 999.0
  guard pn_snapshot(wall) == original && pn_snapshot(source) == before else {
    raise Failure("named selection receiver ownership differs")
  }
  let result : Json = {
    "evidence": "self-authored physical-name public receiver",
    "wall": original,
    "line": pn_snapshot(line),
    "outlet": pn_snapshot(outlet),
    "declared": pn_snapshot(declared),
    "empty_name": pn_snapshot(empty_name),
    "source_unchanged": true,
    "ownership_isolated": true,
  }
  println(result.stringify())
}
