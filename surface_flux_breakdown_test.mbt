///|
test "flux breakdown five families preserve mixed dimension order and owned arrays" {
  let nodes : Array[@gmsh.Node] = []
  let elements : Array[@gmsh.Element] = []
  for i, kind in [2, 3, 9, 10, 16] {
    let base = integral_surface(kind)
    for n in base.nodes() {
      nodes.push({ ..n, tag: n.tag + i * 100, })
    }
    let e = base.elements()[0]
    elements.push({
      ..e,
      tag: 201 + i,
      entity: if i % 2 == 0 {
        7
      } else {
        9
      },
      nodes: e.nodes.map(t => t + i * 100),
    })
    if i == 0 {
      elements.push({ ..e, tag: 900, kind: 15, nodes: [e.nodes[0]], })
    }
  }
  let base = @gmsh.mesh(nodes, elements)
  let nodal = integral_field(base, "NodeData", nodes.map(_ => [0.0, 0.0, 2.0]))
  let cell : @gmsh.Field = {
    ..nodal,
    location: "ElementData",
    integers: [7, 3, 5, 0],
    entries: [
      for i in 0..<5 => { tag: 201 + i, values: [0.0, 0.0, 2.0], }
    ],
  }
  let source = integral_with(base, [nodal, cell])
  for frame in [0, 1] {
    let r = source.surface_flux_breakdown(frame, max_elements=5, max_samples=39)
    assert_eq(r.total.to_json(), source.integrate_surface_flux(frame).to_json())
    assert_eq(r.contributions.length(), 5)
    assert_eq(r.total.skipped_lower_dimension, 1)
    for i, row in r.contributions {
      assert_eq(row.element, 201 + i)
      assert_eq(row.input_index, if i == 0 { 0 } else { i + 1 })
      assert_eq(row.kind, [2, 3, 9, 10, 16][i])
      assert_eq(row.entity, if i % 2 == 0 { 7 } else { 9 })
      let tri = i == 0 || i == 2
      qclose(row.flux, if tri { 1.0 } else { 8.0 })
      qclose(row.surface_measure, if tri { 0.5 } else { 4.0 })
      assert_eq(row.samples, if tri { 6 } else { 9 })
      assert_eq(row.zero_measure_samples, 0)
    }
    let area_z = r.total.area_vector[2]
    r.contributions[0].area_vector[2] = 1234.0
    qclose(r.total.area_vector[2], area_z)
    qclose(r.contributions[1].area_vector[2], 4.0)
    qclose(
      source.surface_flux_breakdown(frame).contributions[0].area_vector[2],
      0.5,
    )
  }
}

///|
test "flux breakdown traces closed cancellation exact frames reversed explicit face and compact" {
  let base = flux_curved_volume()
  let fields = [
    integral_field(
      base,
      "NodeData",
      base.nodes().map(_ => [0.0, 0.0, -2.0]),
      step=0,
    ),
    integral_field(
      base,
      "NodeData",
      base.nodes().map(_ => [0.0, 0.0, -4.0]),
      step=1,
      time=[0.5],
    ),
  ]
  for reverse in [false, true] {
    let elements = base.elements()
    elements.push({
      tag: 700,
      kind: 9,
      nodes: if reverse {
        [1, 2, 3, 5, 6, 7]
      } else {
        [1, 3, 2, 7, 6, 5]
      },
      entity: 0,
      physical: [44],
      extra: [],
    })
    let boundary = @gmsh.mesh(base.nodes(), elements, fields~).extract_boundary()
    let skin = boundary.mesh(allow_loss=true)
    for frame in [0, 1] {
      let r = skin.surface_flux_breakdown(frame)
      let speed = (frame + 1).to_double()
      qclose(r.total.flux, if reverse { -2.0 * speed } else { 0.0 })
      assert_eq(r.total.time_step, frame)
      assert_eq(r.total.time, Some(if frame == 0 { 0.25 } else { 0.5 }))
      let wall = r.contributions.filter(c => c.element == 700)
      assert_eq(wall.length(), 1)
      qclose(wall[0].flux, if reverse { -speed } else { speed })
      let dense = skin.compact()
      let restored = @gmsh.decode(
        dense.encode(version="4.1", binary=true, little=false),
      )
      assert_eq(
        restored.elements().map(e => e.tag),
        dense.elements().map(e => e.tag),
      )
      let after = restored.surface_flux_breakdown(frame)
      qclose(after.total.flux, r.total.flux)
      for i, row in after.contributions {
        assert_eq(row.input_index, i)
        assert_eq(row.element, i + 1)
        qclose(row.flux, r.contributions[i].flux)
      }
    }
  }
}

///|
test "flux breakdown rejects budgets coverage frames schemes and scalar input without partial rows" {
  let base = integral_surface(9)
  let vector = integral_field(
    base,
    "NodeData",
    base.nodes().map(_ => [0.0, 0.0, 2.0]),
  )
  let source = integral_with(base, [vector])
  for budget in [-1, 0, 100001] {
    try source.surface_flux_breakdown(0, max_elements=budget) catch {
      _ => ()
    } noraise {
      _ => fail("bad row budget accepted")
    }
  }
  for samples in [-1, 5, 9000001] {
    try source.surface_flux_breakdown(0, max_samples=samples) catch {
      _ => ()
    } noraise {
      _ => fail("bad sample budget accepted")
    }
  }
  for frame in [-1, 1] {
    try source.surface_flux_breakdown(frame) catch {
      _ => ()
    } noraise {
      _ => fail("bad frame accepted")
    }
  }
  let scalar = integral_field(base, "NodeData", base.nodes().map(_ => [2.0]))
  for
    field in [
      scalar,
      {
        ..vector,
        entries: vector.entries[:vector.entries.length() - 1].to_owned(),
      },
      { ..vector, strings: ["velocity", "custom"], },
    ] {
    try integral_with(base, [field]).surface_flux_breakdown(0) catch {
      _ => ()
    } noraise {
      _ => fail("unsupported or incomplete field accepted")
    }
  }
  assert_eq(
    source.surface_flux_breakdown(0, max_elements=1, max_samples=6).contributions.length(),
    1,
  )
}

///|
test "flux breakdown keeps aggregate range cancellation and rejects nonrepresentable detail" {
  let base = qmesh(2, [
    [0.0, 0.0, 0.0],
    [1.0e100, 0.0, 0.0],
    [0.0, 1.0e100, 0.0],
  ])
  let e = base.elements()[0]
  let source = @gmsh.mesh(
    base.nodes(),
    [
      { ..e, tag: 701, },
      { ..e, tag: 702, nodes: [e.nodes[0], e.nodes[2], e.nodes[1]], },
    ],
    fields=[
      integral_field(
        base,
        "NodeData",
        base.nodes().map(_ => [0.0, 0.0, 1.0e200]),
      ),
    ],
  )
  qclose(source.integrate_surface_flux(0).flux, 0.0)
  try source.surface_flux_breakdown(0) catch {
    _ => ()
  } noraise {
    _ => fail("unrepresentable per-face flux silently omitted")
  }
  let zero = qmesh(2, [[0.0, 0.0, 0.0], [1.0, 0.0, 0.0], [2.0, 0.0, 0.0]])
  let r = integral_with(zero, [
    integral_field(zero, "ElementData", [[1.0, 2.0, 3.0]]),
  ]).surface_flux_breakdown(0)
  assert_eq(r.contributions[0].flux, 0.0)
  assert_eq(r.contributions[0].zero_measure_samples, 6)
  assert_eq(r.total.zero_measure_samples, 6)
}
