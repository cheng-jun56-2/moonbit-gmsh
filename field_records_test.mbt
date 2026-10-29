///|
fn fr_source() -> @gmsh.Mesh raise {
  @gmsh.mesh(
    [
      { tag: 50, xyz: [0.0, 3.0, 0.0], dim: -1, entity: 0, parameters: [], },
      { tag: 7, xyz: [1.0, 0.0, 0.0], dim: -1, entity: 0, parameters: [], },
    ],
    [
      {
        tag: 7,
        kind: 15,
        nodes: [7],
        entity: 1,
        physical: [9],
        extra: [1, 17],
      },
      { tag: 77, kind: 1, nodes: [7, 7], entity: 3, physical: [8], extra: [], },
    ],
    fields=[
      {
        location: "NodeData",
        strings: ["same", "", "extra"],
        reals: [0.5, 7.25],
        integers: [8, 1, 2, 31, 90],
        entries: [{ tag: 50, values: [30.0], }, { tag: 7, values: [10.0], }],
      },
      {
        location: "NodeData",
        strings: ["same", "named"],
        reals: [],
        integers: [2, 3, 1],
        entries: [{ tag: 7, values: [1.0, 2.0, 3.0], }],
      },
      {
        location: "ElementData",
        strings: ["same", "named-cell"],
        reals: [0.25],
        integers: [4, 9, 2, 0],
        entries: [
          { tag: 7, values: [9.0, 8.0, 7.0, 6.0, 5.0, 4.0, 3.0, 2.0, 1.0], },
          { tag: 77, values: [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0], },
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
    unknown=[{ name: "Opaque", body: "original indices\n", }],
  )
}

///|
test "field records raw order headers descriptors and association" {
  let mesh = fr_source()
  let node = mesh.field_records("NodeData", 7, [1, 0])
  assert_eq(node.records.map(r => r.field.field_index), [1, 0])
  assert_eq(node.records.map(r => r.values), [[1.0, 2.0, 3.0], [10.0]])
  assert_eq(node.records[0].field.time, None)
  assert_eq(node.records[0].field.interpolation_scheme, Some("named"))
  assert_eq(node.records[1].strings, ["same", "", "extra"])
  assert_eq(node.records[1].reals, [0.5, 7.25])
  assert_eq(node.records[1].integers, [8, 1, 2, 31, 90])
  assert_eq(node.unknown_section_names, ["Opaque"])
  assert_true(node.element is None)
  assert_eq(node.nodes.map(n => n.tag), [7])
  let cell = mesh.field_records("ElementData", 7, [2])
  assert_eq(cell.records[0].values, [
    9.0, 8.0, 7.0, 6.0, 5.0, 4.0, 3.0, 2.0, 1.0,
  ])
  assert_eq(cell.element.unwrap().physical, [9])
  assert_eq(cell.element.unwrap().extra, [1, 17])
}

///|
test "field records sparse failures and selectors return no partial query" {
  let mesh = fr_source()
  let reject = fn(location, tag, indices) {
    try {
      ignore(mesh.field_records(location, tag, indices))
      false
    } catch {
      _ => true
    }
  }
  assert_true(reject("node", 7, [0]))
  assert_true(reject("NodeData", 7, []))
  assert_true(reject("NodeData", 7, [0, 0]))
  assert_true(reject("NodeData", 7, [-1]))
  assert_true(reject("NodeData", 7, [4]))
  assert_true(reject("NodeData", 7, [0, 2]))
  assert_true(reject("ElementData", 7, [0]))
  assert_true(reject("NodeData", 999, [0]))
  assert_true(reject("ElementData", 999, [2]))
  assert_true(reject("NodeData", 50, [0, 1]))
  assert_true(reject("NodeData", 7, [0, 3]))
  assert_eq(mesh.field_records("NodeData", 7, [0]).records[0].values, [10.0])
}

///|
test "field records deep ownership and repeated legal element roles" {
  let mesh = fr_source()
  let before = mesh.fields().to_json()
  let indices = [2]
  let first = mesh.field_records("ElementData", 77, indices)
  let second = mesh.field_records("ElementData", 77, indices)
  assert_eq(first.nodes.map(n => n.tag), [7, 7])
  first.nodes[0].xyz[0] = 99.0
  first.element.unwrap().nodes[0] = 50
  first.records[0].strings[0] = "changed"
  first.records[0].reals[0] = 999.0
  first.records[0].integers[0] = 99
  first.records[0].values[0] = 99.0
  first.unknown_section_names[0] = "changed"
  indices[0] = 0
  assert_eq(first.nodes[1].xyz, [1.0, 0.0, 0.0])
  assert_eq(mesh.fields().to_json(), before)
  assert_eq(
    mesh.field_records("ElementData", 77, [2]).to_json(),
    second.to_json(),
  )
  assert_eq(mesh.nodes()[1].xyz, [1.0, 0.0, 0.0])
  assert_eq(mesh.elements()[1].nodes, [7, 7])
}

///|
test "field records all27 ordered roles and exact raw extremes" {
  let nodes : Array[@gmsh.Node] = [
    for i in 0..<27 => {
      {
        tag: i + 1,
        xyz: [(i + 1).to_double(), 0.0, 0.0],
        dim: -1,
        entity: 0,
        parameters: [],
      }
    }
  ]
  let mesh = @gmsh.mesh(
    nodes,
    [
      {
        tag: 1,
        kind: 12,
        nodes: [
          for i in 0..<27 => i + 1
        ],
        entity: 0,
        physical: [],
        extra: [],
      },
    ],
    fields=[
      {
        location: "ElementData",
        strings: ["raw"],
        reals: [],
        integers: [0, 3, 1],
        entries: [{ tag: 1, values: [1.0e308, 1.0e-300, -1.0e308], }],
      },
    ],
  )
  let result = mesh.field_records("ElementData", 1, [0])
  assert_eq(result.nodes.map(n => n.tag), [ for i in 0..<27 => i + 1 ])
  assert_eq(result.records[0].values, [1.0e308, 1.0e-300, -1.0e308])
}

///|
test "field records exact existing1024 section budget" {
  let node : @gmsh.Node = {
    tag: 1,
    xyz: [0.0, 0.0, 0.0],
    dim: -1,
    entity: 0,
    parameters: [],
  }
  let mesh = @gmsh.mesh(
    [node],
    [],
    fields=[
      for i in 0..<1024 => {
        {
          location: "NodeData",
          strings: ["same"],
          reals: [],
          integers: [i, 1, 1],
          entries: [{ tag: 1, values: [i.to_double()], }],
        }
      }
    ],
  )
  let records = mesh.field_records(
    "NodeData",
    1,
    [
      for i in 0..<1024 => 1023 - i
    ],
  )
  assert_eq(records.records.length(), 1024)
  assert_eq(records.records[0].values, [1023.0])
  assert_eq(records.records[1023].field.field_index, 0)
  let rejected = try {
    ignore(mesh.field_records("NodeData", 1, [ for _ in 0..<1025 => 0 ]))
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}
