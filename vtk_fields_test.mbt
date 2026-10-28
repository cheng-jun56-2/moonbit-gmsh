///|
test "VTK fields groups both associations with source aliases and requested report order" {
  let source = vtk_field_fixture()
  let out = source.vtk_fields([5, 1, 0], allow_loss=true)
  assert_eq(out.fields.map(f => f.field.field_index), [5, 1, 0])
  assert_eq(out.fields.map(f => f.value_array), [
    "gmsh_value_5", "gmsh_value_1", "gmsh_value_0",
  ])
  assert_eq(out.fields.map(f => f.field.components), [9, 3, 1])
  assert_eq(out.omitted_field_indices, [2, 3, 4])
  assert_eq(out.losses, [
    "msh_field_headers_not_in_vtk", "other_field_sections_omitted",
  ])
  assert_true(
    out.text.contains("POINT_DATA 7\nFIELD FieldData 3\ngmsh_value_1"),
  )
  assert_true(out.text.contains("CELL_DATA 1\nFIELD FieldData 2\ngmsh_value_5"))
  assert_true(
    out.text.contains("gmsh_tag 1 7 int\n1\n2\n3\n4\n5\n6\n2147483647\n"),
  )
  assert_true(out.text.contains("gmsh_tag 1 1 int\n201\n"))
  assert_eq(out.source_version, "4.1")
}

///|
test "VTK fields owns raw metadata and keeps distinct equal source records" {
  let base = vtk_field_fixture()
  let fields = base.fields()
  fields[1] = fields[0]
  let source = @gmsh.mesh(base.nodes(), base.elements(), fields~)
  let before = source.fields().to_json()
  let out = source.vtk_fields([1, 0], allow_loss=true)
  assert_eq(out.fields.map(f => f.field.field_index), [1, 0])
  assert_eq(out.fields.map(f => f.value_array), ["gmsh_value_1", "gmsh_value_0"])
  assert_eq(out.fields[0].strings, out.fields[1].strings)
  assert_eq(out.fields[0].field.time_step, 3)
  assert_eq(out.fields[0].field.time, Some(0.75))
  assert_true(out.losses.contains("other_association_tags_not_in_vtk"))
  out.fields[0].strings[0] = "edited"
  out.fields[0].reals[0] = 88.0
  out.fields[0].integers[0] = -1
  out.fields.clear()
  assert_eq(source.fields().to_json(), before)
}

///|
test "VTK fields validates whole selection without filling or inspecting omitted sparse fields" {
  let source = vtk_field_fixture()
  for indices in [[], [-1], [6], [0, 0], Array::make(1025, 0)] {
    try source.vtk_fields(indices, allow_loss=true) catch {
      _ => ()
    } noraise {
      _ => fail("invalid selection accepted")
    }
  }
  try source.vtk_fields([0, 3]) catch {
    _ => ()
  } noraise {
    _ => fail("loss opt-in missing")
  }
  for index in [0, 3] {
    let fields = source.fields()
    let f = fields[index]
    let entries = if index == 0 {
      f.entries.filter(d => d.tag != 2147483647)
    } else {
      []
    }
    let integers = f.integers.copy()
    integers[2] = entries.length()
    fields[index] = { ..f, entries, integers, }
    let sparse = @gmsh.mesh(source.nodes(), source.elements(), fields~)
    try sparse.vtk_fields([2, 0, 3], allow_loss=true) catch {
      _ => ()
    } noraise {
      _ => fail("missing selected tuple was filled")
    }
    let allowed = if index == 0 { [1, 4] } else { [0, 4] }
    assert_eq(sparse.vtk_fields(allowed, allow_loss=true).fields.length(), 2)
  }
  let empty = @gmsh.mesh([], [], fields=[
    {
      location: "NodeData",
      strings: ["node"],
      reals: [],
      integers: [0, 1, 0],
      entries: [],
    },
    {
      location: "ElementData",
      strings: ["cell"],
      reals: [],
      integers: [0, 9, 0],
      entries: [],
    },
  ])
  let text = empty.vtk_fields([1, 0], allow_loss=true).text
  assert_true(
    text.contains("POINT_DATA 0\nFIELD FieldData 2\ngmsh_value_0 1 0 double\n"),
  )
  assert_true(
    text.contains("CELL_DATA 0\nFIELD FieldData 2\ngmsh_value_1 9 0 double\n"),
  )
  let nodes : Array[@gmsh.Node] = [
    for i in 0..<18 => {
      { tag: i + 1, xyz: [0.0, 0.0, 0.0], dim: -1, entity: 0, parameters: [], }
    }
  ]
  let other = @gmsh.mesh(
    nodes,
    [
      {
        tag: 201,
        kind: 13,
        nodes: nodes.map(n => n.tag),
        entity: 0,
        physical: [],
        extra: [],
      },
    ],
    fields=[
      {
        location: "NodeData",
        strings: ["data"],
        reals: [],
        integers: [0, 1, 18],
        entries: nodes.map(n => { tag: n.tag, values: [1.0], }),
      },
    ],
  )
  try other.vtk_fields([0], allow_loss=true) catch {
    _ => ()
  } noraise {
    _ => fail("unsupported VTK family accepted")
  }
}
