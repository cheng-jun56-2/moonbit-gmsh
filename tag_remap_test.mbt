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
fn rt_rejected(
  source : @gmsh.Mesh,
  ns : Array[@gmsh.TagMapping],
  es : Array[@gmsh.TagMapping],
) -> Bool {
  try {
    ignore(source.remap_tags(ns, es))
    false
  } catch {
    _ => true
  }
}

///|
test "tag remap simultaneous swaps cycles original keys and ordered high roles" {
  let mapped = rt_source().remap_tags(rt_node_maps(), rt_element_maps())
  assert_eq(mapped.nodes().map(n => n.tag), [100, 7, 2147483647, 3, 150, 50, 90])
  assert_eq(mapped.elements().map(e => e.tag), [700, 7])
  assert_eq(mapped.elements().map(e => e.kind), [8, 9])
  assert_eq(mapped.elements()[0].nodes, [3, 2147483647, 150])
  assert_eq(mapped.elements()[1].nodes, [3, 2147483647, 100, 150, 50, 90])
  assert_eq(mapped.nodes()[1].xyz, [9.0, 9.0, 9.0])
  assert_eq(mapped.nodes()[4].parameters, [0.5, 0.0])
}

///|
test "tag remap complete raw fields and semantic integer labels stay distinct" {
  let source = rt_source()
  let mapped = source.remap_tags(rt_node_maps(), rt_element_maps())
  let fields = mapped.fields()
  for i, original in source.fields() {
    assert_eq(fields[i].strings, original.strings)
    assert_eq(fields[i].reals, original.reals)
    assert_eq(fields[i].integers, original.integers)
    assert_eq(
      fields[i].entries.map(d => d.values),
      original.entries.map(d => d.values),
    )
  }
  assert_eq(fields[0].entries.map(d => d.tag), [
    2147483647, 100, 7, 3, 150, 50, 90,
  ])
  assert_eq(fields[1].entries.map(d => d.tag), [700, 7])
  assert_eq(fields[0].entries[2].values, [99.0])
  assert_eq(fields[1].entries[1].values, [
    1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0,
  ])
  assert_eq(fields[4].entries.map(d => d.tag), [100, 7, 2147483647])
  assert_true(fields[3].entries.is_empty())
  assert_eq(fields[0].integers, [8, 1, 7, 31, 90])
  assert_eq(mapped.entities().to_json(), source.entities().to_json())
  assert_eq(
    mapped.physical_names().to_json(),
    source.physical_names().to_json(),
  )
  assert_eq(mapped.elements().map(e => e.entity), [3, 7])
}

///|
test "tag remap inverse identity and empty domains" {
  let source = rt_source()
  let mapped = source.remap_tags(rt_node_maps(), rt_element_maps())
  let ns = rt_node_maps().map(r => @gmsh.TagMapping::{
    old_tag: r.new_tag,
    new_tag: r.old_tag,
  })
  let es = rt_element_maps().map(r => @gmsh.TagMapping::{
    old_tag: r.new_tag,
    new_tag: r.old_tag,
  })
  assert_eq(rt_snapshot(mapped.remap_tags(ns, es)), rt_snapshot(source))
  let identity_ns = source
    .nodes()
    .map(n => @gmsh.TagMapping::{ old_tag: n.tag, new_tag: n.tag, })
  let identity_es = source
    .elements()
    .map(e => @gmsh.TagMapping::{ old_tag: e.tag, new_tag: e.tag, })
  assert_eq(
    rt_snapshot(source.remap_tags(identity_ns, identity_es)),
    rt_snapshot(source),
  )
  let empty = @gmsh.mesh([], [], version="4.1")
  assert_eq(rt_snapshot(empty.remap_tags([], [])), rt_snapshot(empty))
  let points = source.node_cloud(source.nodes().map(n => n.tag))
  let remapped_points = points.remap_tags(rt_node_maps(), [])
  assert_eq(remapped_points.nodes().map(n => n.tag), [
    100, 7, 2147483647, 3, 150, 50, 90,
  ])
  assert_true(
    remapped_points.elements().is_empty() &&
    remapped_points.fields()[1].entries.is_empty(),
  )
}

///|
test "tag remap rejects incomplete unknown duplicate and invalid destination maps atomically" {
  let source = rt_source()
  let before = rt_snapshot(source)
  assert_true(
    rt_rejected(
      source,
      rt_node_maps().filter(r => r.old_tag != 7),
      rt_element_maps(),
    ),
  )
  assert_true(rt_rejected(source, rt_node_maps(), []))
  let ns = rt_node_maps()
  ns[1] = ns[0]
  assert_true(rt_rejected(source, ns, rt_element_maps()))
  let ns = rt_node_maps()
  ns[1] = { ..ns[1], new_tag: ns[0].new_tag, }
  assert_true(rt_rejected(source, ns, rt_element_maps()))
  let ns = rt_node_maps()
  ns[0] = { ..ns[0], old_tag: 700, }
  assert_true(rt_rejected(source, ns, rt_element_maps()))
  let es = rt_element_maps()
  es[1] = { ..es[1], new_tag: es[0].new_tag, }
  assert_true(rt_rejected(source, rt_node_maps(), es))
  let es = rt_element_maps()
  es[1] = { ..es[1], old_tag: 2147483647, }
  assert_true(rt_rejected(source, rt_node_maps(), es))
  for bad in [0, -1] {
    let ns = rt_node_maps()
    ns[0] = { ..ns[0], new_tag: bad, }
    assert_true(rt_rejected(source, ns, rt_element_maps()))
  }
  assert_eq(rt_snapshot(source), before)
}

///|
test "tag remap requires explicit opaque removal without changing source" {
  let source = rt_source()
  let with_unknown = @gmsh.mesh(
    source.nodes(),
    source.elements(),
    entities=source.entities(),
    names=source.physical_names(),
    fields=source.fields(),
    unknown=[{ name: "Opaque", body: "references7\n", }],
    version=source.source_version(),
  )
  assert_true(rt_rejected(with_unknown, rt_node_maps(), rt_element_maps()))
  assert_eq(
    rt_snapshot(
      with_unknown
      .without_unknown()
      .remap_tags(rt_node_maps(), rt_element_maps()),
    ),
    rt_snapshot(source.remap_tags(rt_node_maps(), rt_element_maps())),
  )
  assert_eq(with_unknown.unknown_sections().length(), 1)
}

///|
test "tag remap source request and all writable result arrays remain owned" {
  let source = rt_source()
  let before = rt_snapshot(source)
  let ns = rt_node_maps()
  let es = rt_element_maps()
  let mapped = source.remap_tags(ns, es)
  let original = rt_snapshot(mapped)
  let nodes = mapped.nodes()
  let elements = mapped.elements()
  let fields = mapped.fields()
  let entities = mapped.entities()
  nodes[0].xyz[0] = 99.0
  nodes[0].parameters[0] = 99.0
  elements[0].nodes[0] = 99
  elements[0].physical[0] = 99
  fields[0].integers[0] = 99
  fields[0].entries[0].values[0] = 99.0
  entities[0].physical[0] = 99
  ns[0] = { old_tag: 7, new_tag: 99, }
  es[0] = { old_tag: 700, new_tag: 99, }
  assert_eq(rt_snapshot(source), before)
  assert_eq(rt_snapshot(mapped), original)
  assert_eq(
    rt_snapshot(source.remap_tags(rt_node_maps(), rt_element_maps())),
    original,
  )
}
