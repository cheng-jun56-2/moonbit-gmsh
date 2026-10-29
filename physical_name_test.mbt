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
fn pn_with(
  source : @gmsh.Mesh,
  names : Array[@gmsh.PhysicalName],
  unknown : Array[@gmsh.Section],
) -> @gmsh.Mesh raise {
  @gmsh.mesh(
    source.nodes(),
    source.elements(),
    entities=source.entities(),
    names~,
    fields=source.fields(),
    unknown~,
    version=source.source_version(),
  )
}

///|
test "physical name selection exact dimension Unicode and original field rows" {
  let source = pn_source()
  let wall = source.select_physical_name(2, "热壁 面")
  assert_eq(wall.elements().map(e => e.tag), [700])
  assert_eq(wall.nodes().map(n => n.tag), [50, 7, 90])
  assert_eq(wall.fields()[0].entries.map(d => d.tag), [7, 50, 90])
  assert_eq(wall.fields()[0].integers, [8, 1, 3, 31, 90])
  assert_eq(wall.fields()[1].entries[0].values, [
    1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0,
  ])
  assert_true(wall.fields()[2].entries.is_empty())
  let line = source.select_physical_name(1, "热壁 面")
  assert_eq(line.elements().map(e => e.tag), [3])
  assert_eq(line.fields()[0].integers, [8, 1, 2, 31, 90])
  assert_true(line.fields()[1].entries.is_empty())
}

///|
test "physical name selection declared empty and empty literal name stay legal" {
  let source = pn_source()
  for
    selected in [
      source.select_physical_name(2, "declared-only"),
      source.select_physical_name(0, ""),
    ] {
    assert_true(selected.nodes().is_empty() && selected.elements().is_empty())
    assert_eq(selected.fields().length(), 4)
    assert_true(
      selected.fields().all(f => f.entries.is_empty() && f.integers[2] == 0),
    )
    assert_eq(selected.entities().to_json(), source.entities().to_json())
    assert_eq(
      selected.physical_names().to_json(),
      source.physical_names().to_json(),
    )
  }
}

///|
test "physical name selection ambiguity rejects new query not legal source or numeric API" {
  let source = pn_source()
  let names = source.physical_names()
  names.push({ dim: 2, tag: 66, name: "热壁 面", })
  let ambiguous = pn_with(source, names, [])
  assert_eq(ambiguous.select_physical(2, 44).elements().map(e => e.tag), [700])
  assert_true(ambiguous.select_physical(2, 66).elements().is_empty())
  let rejected = try {
    ignore(ambiguous.select_physical_name(2, "热壁 面"))
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
  assert_eq(ambiguous.physical_names().length(), 6)
  assert_eq(
    ambiguous.select_physical_name(1, "热壁 面").elements().map(e => e.tag),
    [3],
  )
  names[5] = { dim: 2, tag: 66, name: "44", }
  let literal = pn_with(source, names, [])
  assert_true(literal.select_physical_name(2, "44").elements().is_empty())
}

///|
test "physical name selection missing exact labels and old opaque gate" {
  let source = pn_source()
  for
    request in [
      (-1, "热壁 面"),
      (4, "热壁 面"),
      (3, "热壁 面"),
      (2, "热壁"),
      (2, "OUTLET"),
      (2, "44"),
      (2, ""),
    ] {
    let (dimension, name) = request
    let rejected = try {
      ignore(source.select_physical_name(dimension, name))
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
  let with_context = pn_with(source, source.physical_names(), [
    { name: "Opaque", body: "references\n", },
  ])
  let rejected = try {
    ignore(with_context.select_physical_name(2, "热壁 面"))
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
  assert_eq(
    pn_snapshot(
      with_context.without_unknown().select_physical_name(2, "热壁 面"),
    ),
    pn_snapshot(source.select_physical(2, 44)),
  )
  assert_eq(with_context.unknown_sections().length(), 1)
}

///|
test "physical name selection result owns complete existing subset context" {
  let source = pn_source()
  let before = pn_snapshot(source)
  let selected = source.select_physical_name(2, "热壁 面")
  let result_before = pn_snapshot(selected)
  let nodes = selected.nodes()
  let fields = selected.fields()
  let elements = selected.elements()
  let entities = selected.entities()
  nodes[0].xyz[0] = 99.0
  nodes[0].parameters[0] = 99.0
  fields[0].entries[0].values[0] = 99.0
  fields[0].integers[0] = 99
  elements[0].nodes[0] = 50
  entities[0].physical[0] = 99
  assert_eq(pn_snapshot(source), before)
  assert_eq(pn_snapshot(selected), result_before)
  assert_eq(
    pn_snapshot(source.select_physical_name(2, "热壁 面")),
    result_before,
  )
}
