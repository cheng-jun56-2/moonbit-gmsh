///|
fn selection_fixture(unknown? : Array[@gmsh.Section] = []) -> @gmsh.Mesh raise {
  let base = normal_graph()
  let nodes = base
    .nodes()
    .map(n => { ..n, dim: 2, entity: 7, parameters: [n.xyz[0], n.xyz[1]], })
  nodes.push({
    tag: 999,
    xyz: [2.0, 2.0, 2.0],
    dim: 0,
    entity: 19,
    parameters: [],
  })
  @gmsh.mesh(
    nodes,
    [{ ..base.elements()[0], entity: 7, physical: [44], }],
    entities=[
      { dim: 0, tag: 19, bounds: [2.0, 2.0, 2.0], physical: [], boundary: [], },
      {
        dim: 2,
        tag: 7,
        bounds: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
        physical: [44],
        boundary: [],
      },
    ],
    names=[
      { dim: 2, tag: 44, name: "wall", },
      { dim: 1, tag: 55, name: "unused", },
    ],
    fields=[
      {
        location: "NodeData",
        strings: ["温度"],
        reals: [],
        integers: [0, 1, 2],
        entries: [{ tag: 1, values: [300.0], }, { tag: 6, values: [1.0e-250], }],
      },
      {
        location: "NodeData",
        strings: ["velocity", ""],
        reals: [0.25, 5.0],
        integers: [3, 3, 7, 17, 99],
        entries: nodes.map(n => { tag: n.tag, values: [n.xyz[0], -0.0, 2.0], }),
      },
      {
        location: "ElementData",
        strings: ["stress", "custom_scheme"],
        reals: [0.5],
        integers: [9, 9, 1, 0, -7],
        entries: [
          { tag: 201, values: [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0], },
        ],
      },
      {
        location: "NodeData",
        strings: ["empty"],
        reals: [],
        integers: [0, 1, 0],
        entries: [],
      },
    ],
    unknown~,
    version="4.1",
  )
}

///|
test "field selection preserves raw ordered sections and all mesh metadata" {
  let source = selection_fixture()
  let fields = source.fields()
  let selected = source.select_fields([3, 2, 0])
  assert_eq(
    selected.fields().to_json(),
    [fields[3], fields[2], fields[0]].to_json(),
  )
  assert_eq(selected.nodes().to_json(), source.nodes().to_json())
  assert_eq(selected.elements().to_json(), source.elements().to_json())
  assert_eq(selected.entities().to_json(), source.entities().to_json())
  assert_eq(
    selected.physical_names().to_json(),
    source.physical_names().to_json(),
  )
  assert_eq(selected.source_version(), "4.1")
  assert_eq(selected.field_frames().map(f => f.field_index), [0, 1, 2])
  assert_eq(selected.field_frames().map(f => f.entries), [0, 1, 2])
  assert_eq(
    selected.field_frames()[1].interpolation_scheme,
    Some("custom_scheme"),
  )
  let vector = source.select_fields([1])
  assert_eq(vector.field_frames()[0].field_index, 0)
  assert_eq(vector.field_frames()[0].time_step, 3)
  assert_eq(vector.field_frames()[0].time, Some(0.25))
  assert_eq(vector.fields()[0].entries[6].tag, 999)
  let copied = vector.fields()
  copied[0].entries[0].values[0] = 999.0
  assert_eq(vector.fields().to_json(), [fields[1]].to_json())
  assert_eq(source.fields().to_json(), fields.to_json())
  let geometry = source.select_fields([])
  assert_true(geometry.fields().is_empty())
  assert_eq(geometry.nodes().to_json(), source.nodes().to_json())
  assert_eq(geometry.elements().to_json(), source.elements().to_json())
}

///|
test "field selection validates indices without merging equal source records" {
  let source = selection_fixture()
  let before = source.fields().to_json()
  for indices in [[-1], [4], [0, 0], Array::make(1025, 0)] {
    try source.select_fields(indices) catch {
      _ => ()
    } noraise {
      _ => fail("invalid field selection accepted")
    }
  }
  assert_eq(source.fields().to_json(), before)
  let fields = source.fields()
  fields.push(fields[0])
  let repeated = @gmsh.mesh(
    source.nodes(),
    source.elements(),
    entities=source.entities(),
    names=source.physical_names(),
    fields~,
    version=source.source_version(),
  )
  assert_eq(
    repeated.select_fields([4, 0]).fields().to_json(),
    [fields[0], fields[0]].to_json(),
  )
}

///|
test "field selection preserves opaque context only for validated identity" {
  let source = selection_fixture(unknown=[
    { name: "FrameHints", body: "opaque\n", },
  ])
  let identity = source.select_fields([0, 1, 2, 3])
  assert_eq(identity.fields().to_json(), source.fields().to_json())
  assert_eq(
    identity.unknown_sections().to_json(),
    source.unknown_sections().to_json(),
  )
  for indices in [[], [1], [1, 0, 2, 3], [0, 0, 2, 3]] {
    try source.select_fields(indices) catch {
      _ => ()
    } noraise {
      _ => fail("opaque context changed without explicit loss")
    }
  }
  assert_eq(
    source.without_unknown().select_fields([1]).fields().to_json(),
    [source.fields()[1]].to_json(),
  )
  let empty = @gmsh.mesh([], [], unknown=source.unknown_sections())
  assert_eq(
    empty.select_fields([]).unknown_sections().to_json(),
    empty.unknown_sections().to_json(),
  )
}
