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
test "node cloud original node domain and isolated request order" {
  let source = pc_source()
  let pc_result = source.node_cloud([2147483647, 7, 50])
  assert_eq(pc_result.nodes().map(n => n.tag), [2147483647, 7, 50])
  assert_eq(pc_result.nodes()[0].xyz, [9.0, 9.0, 9.0])
  assert_true(pc_result.elements().is_empty())
  assert_eq(source.subset([7]).nodes().map(n => n.tag), [90])
  assert_eq(source.node_cloud([7]).nodes().map(n => n.tag), [7])
  assert_eq(source.node_cloud([7]).fields()[0].entries[0].values, [20.0])
}

///|
test "node cloud raw sparse fields and cell numeric collision stay separate" {
  let pc_result = pc_source().node_cloud([2147483647, 7, 50])
  let fields = pc_result.fields()
  assert_eq(fields.length(), 5)
  assert_eq(fields[0].entries.map(d => d.tag), [7, 50, 2147483647])
  assert_eq(fields[0].integers, [8, 1, 3, 31, 90])
  assert_eq(fields[0].strings, ["temperature", "", "extra"])
  assert_eq(fields[0].reals, [0.5, 7.25])
  assert_eq(fields[1].location, "ElementData")
  assert_true(fields[1].entries.is_empty())
  assert_eq(fields[1].integers, [8, 9, 0, 0, 92])
  assert_eq(fields[2].entries.map(d => d.tag), [2147483647, 50, 7])
  assert_true(fields[3].entries.is_empty())
  assert_eq(fields[4].strings, ["tensor", "raw-node-scheme"])
  assert_eq(fields[4].entries.map(d => d.tag), [50, 2147483647, 7])
  let all_nodes = pc_source().node_cloud([90, 2147483647, 7, 50])
  assert_eq(all_nodes.fields()[4].entries.length(), 3)
  assert_true(all_nodes.elements().is_empty())
}

///|
test "node cloud empty and complete original classification metadata" {
  let source = pc_source()
  let empty = source.node_cloud([])
  assert_true(empty.nodes().is_empty() && empty.elements().is_empty())
  assert_eq(empty.fields().length(), 5)
  assert_true(
    empty.fields().all(f => f.entries.is_empty() && f.integers[2] == 0),
  )
  assert_eq(empty.entities().to_json(), source.entities().to_json())
  assert_eq(empty.physical_names().to_json(), source.physical_names().to_json())
  let mixed = source.node_cloud([7, 90, 2147483647])
  assert_eq(mixed.nodes().map(n => n.tag), [7, 90, 2147483647])
  assert_eq(mixed.nodes().map(n => n.dim), [2, 0, 2])
  assert_eq(mixed.nodes()[0].parameters, [1.0, 0.0])
}

///|
test "node cloud rejects missing duplicate cell-only tags and old opaque context" {
  let source = pc_source()
  for tags in [[7, 7], [700], [7, 999], [0], [-1]] {
    let rejected = try {
      ignore(source.node_cloud(tags))
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
  let pc_unknown = @gmsh.mesh(
    source.nodes(),
    source.elements(),
    entities=source.entities(),
    names=source.physical_names(),
    fields=source.fields(),
    unknown=[{ name: "Opaque", body: "references\n", }],
    version=source.source_version(),
  )
  let rejected = try {
    ignore(pc_unknown.node_cloud([7]))
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
  assert_eq(
    pc_snapshot(pc_unknown.without_unknown().node_cloud([7])),
    pc_snapshot(source.node_cloud([7])),
  )
  assert_eq(pc_unknown.unknown_sections().length(), 1)
}

///|
test "node cloud request and complete Mesh getters remain owned" {
  let source = pc_source()
  let before = pc_snapshot(source)
  let tags = [2147483647, 7, 50]
  let pc_result = source.node_cloud(tags)
  let original = pc_snapshot(pc_result)
  let nodes = pc_result.nodes()
  let fields = pc_result.fields()
  let entities = pc_result.entities()
  nodes[0].xyz[0] = 99.0
  nodes[0].parameters[0] = 99.0
  fields[0].integers[0] = 99
  fields[0].entries[0].values[0] = 99.0
  entities[0].physical[0] = 99
  tags[0] = 90
  assert_eq(pc_snapshot(source), before)
  assert_eq(pc_snapshot(pc_result), original)
  assert_eq(pc_snapshot(source.node_cloud([2147483647, 7, 50])), original)
}
