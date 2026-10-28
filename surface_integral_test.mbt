///|
fn integral_surface(kind : Int) -> @gmsh.Mesh raise {
  if kind == 2 {
    qmesh(2, [[0.0, 0.0, 0.0], [1.0, 0.0, 0.0], [0.0, 1.0, 0.0]])
  } else if kind == 3 {
    qmesh(3, [
      [-1.0, -1.0, 0.0],
      [1.0, -1.0, 0.0],
      [1.0, 1.0, 0.0],
      [-1.0, 1.0, 0.0],
    ])
  } else {
    dr_fixture(kind, [1.0, 1.0, 1.0])
  }
}

///|
fn integral_field(
  m : @gmsh.Mesh,
  location : String,
  values : Array[Array[Double]],
  step? : Int = 7,
  time? : Array[Double] = [0.25],
) -> @gmsh.Field {
  {
    location,
    strings: ["result"],
    reals: time,
    integers: [step, values[0].length(), values.length(), 0],
    entries: values.mapi((i, v) => {
      tag: if location == "NodeData" {
        m.nodes()[i].tag
      } else {
        m.elements()[i].tag
      },
      values: v,
    }),
  }
}

///|
fn integral_with(
  m : @gmsh.Mesh,
  fields : Array[@gmsh.Field],
) -> @gmsh.Mesh raise {
  @gmsh.mesh(m.nodes(), m.elements(), fields~)
}

///|
test "surface integration scalar nodal and cell fields across five families" {
  for kind in [2, 3, 9, 10, 16] {
    let m = integral_surface(kind)
    let tri = kind == 2 || kind == 9
    let nodal = integral_field(
      m,
      "NodeData",
      m
      .nodes()
      .map(n => {
        [
          if tri {
            1.0 + n.xyz[0] + 2.0 * n.xyz[1]
          } else {
            2.0 + n.xyz[0] + 3.0 * n.xyz[1]
          },
        ]
      }),
    )
    let cell = integral_field(m, "ElementData", [[3.0]])
    let source = integral_with(m, [nodal, cell])
    let r = source.integrate_surface_field(0)
    qclose(r.surface_measure, if tri { 0.5 } else { 4.0 })
    qclose(r.integral[0], if tri { 1.0 } else { 8.0 })
    assert_eq(r.samples, if tri { 6 } else { 9 })
    assert_eq(r.elements, 1)
    assert_eq(r.skipped_lower_dimension, 0)
    assert_eq(r.time_step, 7)
    assert_eq(r.time, Some(0.25))
    assert_true(!r.certified_error_bound)
    qclose(
      source.integrate_surface_field(1).integral[0],
      if tri {
        1.5
      } else {
        12.0
      },
    )
  }
}

///|
test "surface integration quadratic nodes vector and tensor components are real data" {
  for kind in [2, 9] {
    let m = integral_surface(kind)
    let f = integral_field(
      m,
      "NodeData",
      m.nodes().map(n => [n.xyz[0] * n.xyz[0]]),
    )
    qclose(
      integral_with(m, [f]).integrate_surface_field(0).integral[0],
      if kind == 2 {
        1.0 / 6.0
      } else {
        1.0 / 12.0
      },
    )
  }
  for kind in [9, 10, 16] {
    let m = integral_surface(kind)
    let f = integral_field(
      m,
      "NodeData",
      m
      .nodes()
      .map(n => {
        let x = n.xyz[0]
        let y = n.xyz[1]
        [x * x, x * y, y * y]
      }),
    )
    let r = integral_with(m, [f]).integrate_surface_field(0)
    let expected = if kind == 9 {
      [1.0 / 12.0, 1.0 / 24.0, 1.0 / 12.0]
    } else {
      [4.0 / 3.0, 0.0, 4.0 / 3.0]
    }
    for k in 0..<3 {
      qclose(r.integral[k], expected[k])
    }
    let tensor = integral_field(m, "ElementData", [
      [
        for k in 0..<9 => (k + 1).to_double()
      ],
    ])
    let r = integral_with(m, [tensor]).integrate_surface_field(0)
    assert_eq(r.components, 9)
    for k in 0..<9 {
      qclose(
        r.integral[k],
        (k + 1).to_double() * (if kind == 9 { 0.5 } else { 4.0 }),
      )
    }
  }
}

///|
test "surface integration exact frame identity coverage and budgets" {
  let m = integral_surface(9)
  let f = integral_field(m, "NodeData", m.nodes().map(_ => [1.0]), step=3, time=[])
  let g = integral_field(m, "NodeData", m.nodes().map(_ => [3.0]), step=4, time=[
    0.5,
  ])
  let source = integral_with(m, [f, g])
  let first = source.integrate_surface_field(0, max_samples=6)
  assert_eq(first.time, None)
  assert_eq(first.time_step, 3)
  qclose(first.integral[0], 0.5)
  let second = source.integrate_surface_field(1)
  assert_eq(second.time, Some(0.5))
  qclose(second.integral[0], 1.5)
  for index in [-1, 2] {
    try source.integrate_surface_field(index) catch {
      _ => ()
    } noraise {
      _ => fail("invalid frame accepted")
    }
  }
  for budget in [-1, 0, 5, 9000001] {
    try source.integrate_surface_field(0, max_samples=budget) catch {
      _ => ()
    } noraise {
      _ => fail("invalid/insufficient budget accepted")
    }
  }
  let partial = { ..f, entries: f.entries[:5].to_owned(), integers: [3, 1, 5], }
  try integral_with(m, [partial]).integrate_surface_field(0) catch {
    _ => ()
  } noraise {
    _ => fail("missing midside data filled with zero")
  }
  let empty : @gmsh.Field = {
    location: "ElementData",
    strings: ["empty"],
    reals: [],
    integers: [0, 1, 0],
    entries: [],
  }
  try integral_with(m, [empty]).integrate_surface_field(0) catch {
    _ => ()
  } noraise {
    _ => fail("missing element data filled with zero")
  }
  let custom = { ..f, strings: ["field", "custom_scheme"], }
  try integral_with(m, [custom]).integrate_surface_field(0) catch {
    _ => ()
  } noraise {
    _ => fail("named interpolation silently treated as Lagrange")
  }
  let volume = dr_fixture(11, [1.0, 1.0, 1.0])
  let volume_field = integral_field(
    volume,
    "NodeData",
    volume.nodes().map(_ => [1.0]),
  )
  try integral_with(volume, [volume_field]).integrate_surface_field(0) catch {
    _ => ()
  } noraise {
    _ => fail("volume silently used as a surface")
  }
}

///|
test "surface integration range protection zero area and signed accumulation" {
  let wide = qmesh(2, [
    [-1.7e308, 0.0, 0.0],
    [1.7e308, 0.0, 0.0],
    [-1.7e308, 1.0, 0.0],
  ])
  let r = integral_with(wide, [
    integral_field(wide, "ElementData", [[1.0e-308]]),
  ]).integrate_surface_field(0)
  dr_relative(r.surface_measure, 1.7e308)
  dr_relative(r.integral[0], 1.7)
  let tiny = qmesh(2, [
    [0.0, 0.0, 0.0],
    [1.0e-100, 0.0, 0.0],
    [0.0, 1.0e-100, 0.0],
  ])
  qclose(
    integral_with(tiny, [
      integral_field(tiny, "NodeData", tiny.nodes().map(_ => [1.0e200])),
    ]).integrate_surface_field(0).integral[0],
    0.5,
  )
  let flat = qmesh(2, [[0.0, 0.0, 0.0], [1.0, 0.0, 0.0], [2.0, 0.0, 0.0]])
  let zero = integral_with(flat, [integral_field(flat, "ElementData", [[5.0]])]).integrate_surface_field(
    0,
  )
  assert_eq(zero.integral, [0.0])
  assert_eq(zero.zero_measure_samples, 6)
  let too_large = integral_surface(3)
  try
    integral_with(too_large, [
      integral_field(too_large, "ElementData", [[1.0e308]]),
    ]).integrate_surface_field(0)
  catch {
    _ => ()
  } noraise {
    _ => fail("nonrepresentable integral returned")
  }
  try
    integral_with(tiny, [integral_field(tiny, "ElementData", [[1.0e-200]])]).integrate_surface_field(
      0,
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("nonzero integral underflow silently returned zero")
  }
  let base = integral_surface(2)
  let nodes = base.nodes()
  let cells = base.elements()
  for offset in [2.0, 4.0] {
    let first = nodes.length()
    for n in base.nodes() {
      nodes.push({
        ..n,
        tag: first + n.tag,
        xyz: [n.xyz[0] + offset, n.xyz[1], n.xyz[2]],
      })
    }
    cells.push({
      ..base.elements()[0],
      tag: 201 + first / 3,
      nodes: [first + 1, first + 2, first + 3],
    })
  }
  let m = @gmsh.mesh(nodes, cells)
  let r = integral_with(m, [
    integral_field(m, "ElementData", [[1.0e16], [1.0], [-1.0e16]]),
  ]).integrate_surface_field(0)
  qclose(r.integral[0], 0.5)
}

///|
test "surface integration selected explicit boundary never inherits parent fields" {
  let base = dr_fixture(11, [1.0, 1.0, 1.0])
  let elements = base.elements()
  elements[0] = { ..elements[0], physical: [99], }
  elements.push({
    tag: 700,
    kind: 9,
    nodes: [1, 3, 2, 7, 6, 5],
    entity: 0,
    physical: [44],
    extra: [],
  })
  let body : @gmsh.Field = {
    location: "ElementData",
    strings: ["body"],
    reals: [0.25],
    integers: [0, 1, 1],
    entries: [{ tag: 201, values: [99.0], }],
  }
  let wall : @gmsh.Field = {
    ..body,
    strings: ["wall"],
    entries: [{ tag: 700, values: [3.0], }],
  }
  let flux = integral_field(base, "NodeData", base.nodes().map(_ => [2.0]))
  let m = @gmsh.mesh(base.nodes(), elements, fields=[body, wall, flux])
  let selected = m
    .extract_boundary()
    .mesh(allow_loss=true)
    .select_physical(2, 44)
  qclose(selected.integrate_surface_field(1).integral[0], 1.5)
  qclose(selected.integrate_surface_field(2).integral[0], 1.0)
  try selected.integrate_surface_field(0) catch {
    _ => ()
  } noraise {
    _ => fail("parent field inherited by a face")
  }
  let edges = selected.elements()
  edges.push({
    tag: 900,
    kind: 1,
    nodes: [1, 2],
    entity: 0,
    physical: [],
    extra: [],
  })
  let mixed = @gmsh.mesh(selected.nodes(), edges, fields=selected.fields())
  let r = mixed.integrate_surface_field(1)
  assert_eq(r.skipped_lower_dimension, 1)
  qclose(r.integral[0], 1.5)
}
