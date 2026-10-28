///|
fn t4_nodes() -> Array[@gmsh.Node] {
  [
    { tag: 700, xyz: [0.0, 3.0, 0.0], dim: -1, entity: 0, parameters: [], },
    { tag: 999, xyz: [9.0, 9.0, 9.0], dim: -1, entity: 0, parameters: [], },
    { tag: 90, xyz: [0.0, 0.0, 0.0], dim: -1, entity: 0, parameters: [], },
    {
      tag: 2147483647,
      xyz: [0.0, 0.0, 4.0],
      dim: -1,
      entity: 0,
      parameters: [],
    },
    { tag: 10, xyz: [2.0, 0.0, 0.0], dim: -1, entity: 0, parameters: [], },
  ]
}

///|
fn t4_fields() -> Array[@gmsh.Field] {
  let tags = [2147483647, 90, 999, 10, 700]
  let scalar = [13.0, 1.0, 123.0, 3.0, 7.0]
  let vector = [
    [0.0, 0.0, 4.0],
    [0.0, 0.0, 0.0],
    [9.0, 9.0, 9.0],
    [2.0, 0.0, 0.0],
    [0.0, 3.0, 0.0],
  ]
  let fields : Array[@gmsh.Field] = [
    for components in [1, 3, 9] => {
      {
        location: "NodeData",
        strings: [
          if components == 1 {
            "温度"
          } else {
            "components"
          },
          "",
          "raw extra",
        ],
        reals: [0.5, 7.25],
        integers: [2, components, 5, 17, 42],
        entries: tags.mapi((i, tag) => {
          tag,
          values: if components == 3 {
            vector[i].copy()
          } else {
            [
              for k in 1..<=components => k.to_double() * scalar[i]
            ]
          },
        }),
      }
    }
  ]
  fields.push({
    ..fields[0],
    entries: fields[0].entries.map(d => { ..d, values: [d.values[0] + 100.0], }),
  })
  fields.push({
    ..fields[0],
    strings: ["constant"],
    entries: tags.map(tag => { tag, values: [-7.0], }),
  })
  fields
}

///|
fn t4_mesh(
  fields? : Array[@gmsh.Field] = t4_fields(),
  nodes? : Array[@gmsh.Node] = t4_nodes(),
  roles? : Array[Int] = [90, 10, 700, 2147483647],
  kind? : Int = 4,
) -> @gmsh.Mesh raise {
  @gmsh.mesh(
    nodes,
    [{ tag: 201, kind, nodes: roles, entity: 0, physical: [], extra: [], }],
    fields~,
  )
}

///|
fn t4_reject(
  source : @gmsh.Mesh,
  index : Int,
  tag : Int,
  p : Array[Double],
) -> Unit raise {
  let before = source.fields().to_json()
  let caller = p.copy()
  let rejected = try {
    let _ = source.evaluate_tet4_nodal_field(index, tag, p)
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
  assert_eq(source.fields().to_json(), before)
  assert_eq(p.length(), caller.length())
  for i in 0..<p.length() {
    assert_eq(p[i].reinterpret_as_uint64(), caller[i].reinterpret_as_uint64())
  }
}

///|
test "TET4 field hand-derived scalar vector nine values and exact frame witnesses" {
  let m = t4_mesh()
  let p = [0.25, 0.125, 0.125]
  let scalar = m.evaluate_tet4_nodal_field(0, 201, p)
  assert_eq(scalar.values, [3.75])
  assert_eq(scalar.xyz, [0.5, 0.375, 0.5])
  assert_eq(scalar.weights, [0.5, 0.25, 0.125, 0.125])
  assert_eq(scalar.node_tags, [90, 10, 700, 2147483647])
  assert_eq(scalar.nodal_values, [[1.0], [3.0], [7.0], [13.0]])
  assert_eq(scalar.node_xyz, [
    [0.0, 0.0, 0.0],
    [2.0, 0.0, 0.0],
    [0.0, 3.0, 0.0],
    [0.0, 0.0, 4.0],
  ])
  assert_eq(scalar.strings, ["温度", "", "raw extra"])
  assert_eq(scalar.reals, [0.5, 7.25])
  assert_eq(scalar.integers, [2, 1, 5, 17, 42])
  assert_eq(scalar.field.entries, 5)
  assert_eq(scalar.field.partition, Some(17))
  assert_eq(scalar.field.field_index, 0)
  assert_eq(m.evaluate_tet4_nodal_field(1, 201, p).values, [0.5, 0.375, 0.5])
  assert_eq(m.evaluate_tet4_nodal_field(2, 201, p).values, [
    3.75, 7.5, 11.25, 15.0, 18.75, 22.5, 26.25, 30.0, 33.75,
  ])
  let other = m.evaluate_tet4_nodal_field(3, 201, p)
  assert_eq(other.values, [103.75])
  assert_eq(other.field.name, scalar.field.name)
  assert_eq(other.field.time, scalar.field.time)
  assert_eq(other.field.time_step, scalar.field.time_step)
}

///|
test "TET4 field vertices edges faces interior and constant reproduction" {
  let m = t4_mesh()
  let points = [
    [0.0, 0.0, 0.0],
    [1.0, 0.0, 0.0],
    [0.0, 1.0, 0.0],
    [0.0, 0.0, 1.0],
    [0.5, 0.0, 0.0],
    [0.25, 0.25, 0.0],
    [0.5, 0.25, 0.25],
    [0.25, 0.125, 0.125],
  ]
  let expected = [1.0, 3.0, 7.0, 13.0, 2.0, 3.0, 6.5, 3.75]
  let xyz = [
    [0.0, 0.0, 0.0],
    [2.0, 0.0, 0.0],
    [0.0, 3.0, 0.0],
    [0.0, 0.0, 4.0],
    [1.0, 0.0, 0.0],
    [0.5, 0.75, 0.0],
    [1.0, 0.75, 1.0],
    [0.5, 0.375, 0.5],
  ]
  for i, p in points {
    let r = m.evaluate_tet4_nodal_field(0, 201, p)
    assert_eq(r.values, [expected[i]])
    assert_eq(r.xyz, xyz[i])
    assert_eq(m.evaluate_tet4_nodal_field(4, 201, p).values, [-7.0])
  }
}

///|
test "TET4 field owned caller result headers and nested source witnesses" {
  let m = t4_mesh()
  let before = m.fields().to_json()
  let original_nodes = m.nodes().to_json()
  let p = [0.25, 0.125, 0.125]
  let r = m.evaluate_tet4_nodal_field(0, 201, p)
  p[0] = 0.75
  assert_eq(r.reference, [0.25, 0.125, 0.125])
  r.reference[0] = 0.99
  r.weights[0] = 0.99
  r.node_tags[0] = 999
  r.node_xyz[0][0] = 99.0
  r.nodal_values[0][0] = 99.0
  r.xyz[0] = 99.0
  r.values[0] = 99.0
  r.strings[0] = "changed"
  r.reals[0] = 99.0
  r.integers[0] = 99
  assert_eq(m.fields().to_json(), before)
  assert_eq(m.nodes().to_json(), original_nodes)
  assert_eq(m.evaluate_tet4_nodal_field(0, 201, [0.25, 0.125, 0.125]).values, [
    3.75,
  ])
}

///|
test "TET4 field preserves missing versus explicit time and empty scheme headers" {
  let fields = t4_fields()
  fields[0] = {
    ..fields[0],
    strings: ["温度"],
    reals: [],
    integers: [2, 1, 5],
  }
  fields[3] = {
    ..fields[3],
    strings: ["温度", ""],
    reals: [0.0],
    integers: [2, 1, 5, 0, 91],
  }
  let m = t4_mesh(fields~)
  let absent = m.evaluate_tet4_nodal_field(0, 201, [0.25, 0.125, 0.125])
  let zero = m.evaluate_tet4_nodal_field(3, 201, [0.25, 0.125, 0.125])
  assert_eq(absent.field.time, None)
  assert_eq(absent.field.partition, None)
  assert_eq(absent.reals, [])
  assert_eq(absent.strings, ["温度"])
  assert_eq(zero.field.time, Some(0.0))
  assert_eq(zero.field.partition, Some(0))
  assert_eq(zero.integers, [2, 1, 5, 0, 91])
  assert_eq(zero.values, [103.75])
}

///|
test "TET4 field missing role cannot hide behind zero weight or unrelated count" {
  let fields = t4_fields()
  let partial = fields[0].entries.filter(d => d.tag != 2147483647)
  fields[0] = { ..fields[0], entries: partial, integers: [2, 1, 4, 17, 42], }
  let m = t4_mesh(fields~)
  t4_reject(m, 0, 201, [0.0, 0.0, 0.0])
  t4_reject(m, 0, 201, [0.25, 0.125, 0.125])
  assert_eq(m.evaluate_tet4_nodal_field(1, 201, [0.0, 0.0, 0.0]).values, [
    0.0, 0.0, 0.0,
  ])
}

///|
test "TET4 field rejects unsupported request only and retains existing source acceptance" {
  let m = t4_mesh()
  for index in [-1, 5] {
    t4_reject(m, index, 201, [0.0, 0.0, 0.0])
  }
  t4_reject(m, 0, 202, [0.0, 0.0, 0.0])
  let nan = 0x7ff8000000000000UL.reinterpret_as_double()
  let inf = 0x7ff0000000000000UL.reinterpret_as_double()
  for
    p in [
      [],
      [0.0, 0.0],
      [0.0, 0.0, 0.0, 0.0],
      [-0.01, 0.0, 0.0],
      [0.5, 0.5, 0.01],
      [1.0000000000000002, 0.0, 0.0],
      [nan, 0.0, 0.0],
      [0.0, inf, 0.0],
    ] {
    t4_reject(m, 0, 201, p)
  }
  t4_reject(t4_mesh(kind=2, roles=[90, 10, 700]), 0, 201, [0.0, 0.0, 0.0])
  t4_reject(
    t4_mesh(kind=11, roles=[90, 10, 700, 2147483647, 90, 10, 700, 90, 10, 700]),
    0,
    201,
    [0.0, 0.0, 0.0],
  )
  let fields = t4_fields()
  fields[0] = { ..fields[0], strings: ["named", "custom"], }
  t4_reject(t4_mesh(fields~), 0, 201, [0.0, 0.0, 0.0])
  fields[0] = {
    location: "ElementData",
    strings: ["cell"],
    reals: [],
    integers: [0, 1, 1],
    entries: [{ tag: 201, values: [2.0], }],
  }
  t4_reject(t4_mesh(fields~), 0, 201, [0.0, 0.0, 0.0])
}

///|
test "TET4 field inverted degenerate repeated roles retain parametric meaning" {
  let p = [0.25, 0.125, 0.125]
  let inverted = t4_mesh(roles=[90, 700, 10, 2147483647]).evaluate_tet4_nodal_field(
    0, 201, p,
  )
  assert_eq(inverted.values, [4.25])
  assert_eq(inverted.xyz, [0.25, 0.75, 0.5])
  let nodes = t4_nodes().map(n => { ..n, xyz: [0.0, 0.0, 0.0], })
  let flat = t4_mesh(nodes~)
  assert_eq(flat.evaluate_tet4_nodal_field(0, 201, p).values, [3.75])
  assert_eq(flat.evaluate_tet4_nodal_field(0, 201, p).xyz, [0.0, 0.0, 0.0])
  assert_eq(flat.evaluate_tet4_nodal_field(0, 201, [1.0, 0.0, 0.0]).values, [
    3.0,
  ])
  let repeated = t4_mesh(roles=[90, 10, 700, 90]).evaluate_tet4_nodal_field(
    0, 201, p,
  )
  assert_eq(repeated.node_tags, [90, 10, 700, 90])
  assert_eq(repeated.values, [2.25])
  assert_eq(repeated.xyz, [0.5, 0.375, 0.0])
  repeated.nodal_values[0][0] = 99.0
  repeated.node_xyz[0][0] = 99.0
  assert_eq(repeated.nodal_values[3], [1.0])
  assert_eq(repeated.node_xyz[3], [0.0, 0.0, 0.0])
}

///|
test "TET4 field protected range allows large forward map and rejects nonzero underflow" {
  let nodes = t4_nodes()
  nodes[2] = { ..nodes[2], xyz: [1.6e308, 0.0, 0.0], }
  nodes[4] = { ..nodes[4], xyz: [-1.6e308, 0.0, 0.0], }
  let large = t4_mesh(nodes~).evaluate_tet4_nodal_field(0, 201, [0.5, 0.0, 0.0])
  assert_eq(large.xyz, [0.0, 0.0, 0.0])
  assert_eq(large.values, [2.0])
  let tiny = 1UL.reinterpret_as_double()
  let fields = t4_fields()
  fields[0] = {
    ..fields[0],
    entries: fields[0].entries.map(d => {
      ..d,
      values: [if d.tag == 10 { tiny } else { 0.0 }],
    }),
  }
  t4_reject(t4_mesh(fields~), 0, 201, [0.25, 0.0, 0.0])
  let nodes = t4_nodes().map(n => {
    ..n,
    xyz: [if n.tag == 10 { tiny } else { 0.0 }, 0.0, 0.0],
  })
  t4_reject(t4_mesh(nodes~), 0, 201, [0.25, 0.0, 0.0])
}

///|
test "TET4 field does not replace original constructor datum validation" {
  let base = t4_fields()
  let duplicate = {
    ..base[0],
    entries: [base[0].entries[0], base[0].entries[0]],
    integers: [2, 1, 2],
  }
  let malformed = { ..base[0], integers: [2, 3, 5], }
  let nonfinite = {
    ..base[0],
    entries: base[0].entries.map(d => {
      ..d,
      values: [0x7ff0000000000000UL.reinterpret_as_double()],
    }),
  }
  for f in [duplicate, malformed, nonfinite] {
    let rejected = try {
      let _ = t4_mesh(fields=[f])
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}
