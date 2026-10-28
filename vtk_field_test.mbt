///|
fn vtk_field_fixture() -> @gmsh.Mesh raise {
  let base = integral_surface(9)
  let nodes = base.nodes()
  nodes.push({
    tag: 2147483647,
    xyz: [4.0, 5.0, 6.0],
    dim: -1,
    entity: 0,
    parameters: [],
  })
  let fields : Array[@gmsh.Field] = []
  for j in 0..<6 {
    let nodal = j < 3
    let components = [1, 3, 9][j % 3]
    let tags = if nodal { nodes.map(n => n.tag) } else { [201] }
    fields.push({
      location: if nodal {
        "NodeData"
      } else {
        "ElementData"
      },
      strings: ["field \{j}", ""],
      reals: [0.75, 2.0],
      integers: [3, components, tags.length(), 17, 99],
      entries: tags.mapi((i, _) => {
        let tag = tags[tags.length() - 1 - i]
        @gmsh.Datum::{
          tag,
          values: [
            for k in 0..<components => tag.to_double() + k.to_double() / 4.0
          ],
        }
      }),
    })
  }
  @gmsh.mesh(nodes, base.elements(), fields~, version="4.1")
}

///|
test "VTK field exports both associations and component counts in stored tag order" {
  let source = vtk_field_fixture()
  for j in 0..<6 {
    let out = source.vtk_field(j, allow_loss=true)
    let components = [1, 3, 9][j % 3]
    let tuples = if j < 3 { 7 } else { 1 }
    assert_true(
      out.text.contains("gmsh_value \{components} \{tuples} double\n"),
    )
    assert_true(out.text.contains("gmsh_tag 1 \{tuples} int\n"))
    assert_eq(out.field.field_index, j)
    assert_eq(out.field.components, components)
    assert_eq(out.field.time_step, 3)
    assert_eq(out.field.time, Some(0.75))
    assert_eq(
      out.omitted_field_indices,
      Array::makei(6, i => i).filter(i => i != j),
    )
    assert_eq(out.source_version, "4.1")
  }
  assert_true(
    source.vtk_field(0, allow_loss=true).text.contains(
      "gmsh_value 1 7 double\n1\n2\n3\n4\n5\n6\n2147483647\n",
    ),
  )
  assert_true(
    source.vtk_field(0, allow_loss=true).text.contains(
      "gmsh_tag 1 7 int\n1\n2\n3\n4\n5\n6\n2147483647\n",
    ),
  )
  assert_true(
    source.vtk_field(3, allow_loss=true).text.contains("CELL_DATA 1\n"),
  )
}

///|
test "VTK field keeps owned raw heads and reports actual omissions without interpreting schemes" {
  let base = vtk_field_fixture()
  let fields = base.fields()
  fields[0] = {
    ..fields[0],
    strings: ["速度 samples", "custom_scheme"],
    reals: [],
  }
  let source = @gmsh.mesh(base.nodes(), base.elements(), fields~, unknown=[
    { name: "SolverHints", body: "opaque\n", },
  ])
  let before = source.fields().to_json()
  let out = source.vtk_field(0, allow_loss=true)
  assert_eq(out.strings, fields[0].strings)
  assert_eq(out.reals, [])
  assert_eq(out.integers, fields[0].integers)
  assert_eq(out.field.interpolation_scheme, Some("custom_scheme"))
  assert_eq(out.field.time, None)
  assert_eq(out.losses, [
    "msh_field_headers_not_in_vtk", "other_association_tags_not_in_vtk", "other_field_sections_omitted",
    "mesh_metadata_omitted",
  ])
  out.strings[0] = "changed"
  out.reals.push(1.0)
  out.integers[0] = 99
  out.omitted_field_indices.clear()
  assert_eq(source.fields().to_json(), before)
  assert_true(
    source.vtk(allow_loss=true).contains("MoonGmsh geometry-only export\n"),
  )
  assert_true(!source.vtk(allow_loss=true).contains("POINT_DATA"))
}

///|
test "VTK field rejects incomplete data and invalid queries while permitting empty tuples" {
  let source = vtk_field_fixture()
  for index in [-1, 6] {
    try source.vtk_field(index, allow_loss=true) catch {
      _ => ()
    } noraise {
      _ => fail("invalid frame accepted")
    }
  }
  try source.vtk_field(0) catch {
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
    try sparse.vtk_field(index, allow_loss=true) catch {
      _ => ()
    } noraise {
      _ => fail("missing tuple was filled")
    }
  }
  for location in ["NodeData", "ElementData"] {
    let empty = @gmsh.mesh([], [], fields=[
      {
        location,
        strings: ["empty"],
        reals: [],
        integers: [0, 1, 0],
        entries: [],
      },
    ])
    assert_true(
      empty.vtk_field(0, allow_loss=true).text.contains(
        "gmsh_value 1 0 double\ngmsh_tag 1 0 int\n",
      ),
    )
  }
  let nodes : Array[@gmsh.Node] = [
    for i in 0..<18 => {
      { tag: i + 1, xyz: [0.0, 0.0, 0.0], dim: -1, entity: 0, parameters: [], }
    }
  ]
  let unsupported = @gmsh.mesh(
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
  try unsupported.vtk_field(0, allow_loss=true) catch {
    _ => ()
  } noraise {
    _ => fail("unsupported VTK family accepted")
  }
}
