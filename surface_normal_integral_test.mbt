///|
fn normal_graph() -> @gmsh.Mesh raise {
  qmesh(9, [
    [0.0, 0.0, 0.0],
    [1.0, 0.0, 1.0],
    [0.0, 1.0, 1.0],
    [0.5, 0.0, 0.25],
    [0.5, 0.5, 0.5],
    [0.0, 0.5, 0.25],
  ])
}

///|
test "scalar normal integral couples varying pressure and curved normal analytically" {
  let base = normal_graph()
  let scalar = integral_field(
    base,
    "NodeData",
    base.nodes().map(n => [1.0 + n.xyz[0]]),
  )
  let cell = integral_field(base, "ElementData", [[2.0]])
  let source = integral_with(base, [scalar, cell])
  let r = source.integrate_surface_normal_field(0)
  for i, expected in [-0.5, -5.0 / 12.0, 2.0 / 3.0] {
    qclose(r.normal_integral[i], expected)
    qclose(
      flux_reversed(source).integrate_surface_normal_field(0).normal_integral[i],
      -expected,
    )
  }
  for i, expected in [-2.0 / 3.0, -2.0 / 3.0, 1.0] {
    qclose(
      source.integrate_surface_normal_field(1).normal_integral[i],
      expected,
    )
  }
  assert_eq(r.time_step, 7)
  assert_eq(r.time, Some(0.25))
  assert_eq(r.normal_convention, "stored_node_winding")
  assert_true(!r.certified_error_bound)
  let area = source.integrate_surface_field(0)
  let average = area.integral[0] / area.surface_measure
  assert_true((average * r.area_vector[0] - r.normal_integral[0]).abs() > 0.03)
}

///|
test "scalar normal integral uses full five family interpolation including Quad9 center" {
  for kind in [2, 3, 9, 10, 16] {
    let base = integral_surface(kind)
    let source = integral_with(base, [
      integral_field(base, "NodeData", base.nodes().map(_ => [2.0])),
      integral_field(base, "ElementData", [[-3.0]]),
    ])
    let tri = kind == 2 || kind == 9
    for frame in [0, 1] {
      let r = source.integrate_surface_normal_field(frame)
      qclose(r.normal_integral[0], 0.0)
      qclose(r.normal_integral[1], 0.0)
      qclose(
        r.normal_integral[2],
        (if tri { 0.5 } else { 4.0 }) * (if frame == 0 { 2.0 } else { -3.0 }),
      )
      assert_eq(r.samples, if tri { 6 } else { 9 })
    }
  }
  let quad = integral_surface(10)
  let center = integral_field(
    quad,
    "NodeData",
    quad.nodes().mapi((i, _) => [if i == 8 { 1.0 } else { 0.0 }]),
  )
  qclose(
    integral_with(quad, [center]).integrate_surface_normal_field(0).normal_integral[2],
    16.0 / 9.0,
  )
  let tri = integral_surface(9)
  let quadratic = integral_field(
    tri,
    "NodeData",
    tri.nodes().map(n => [n.xyz[0] * n.xyz[0]]),
  )
  qclose(
    integral_with(tri, [quadratic]).integrate_surface_normal_field(0).normal_integral[2],
    1.0 / 12.0,
  )
}

///|
test "scalar normal integral closed curved boundary obeys volume gradient identity" {
  let base = flux_curved_volume()
  let source = integral_with(base, [
    integral_field(base, "NodeData", base.nodes().map(_ => [2.0]), step=0),
    integral_field(
      base,
      "NodeData",
      base.nodes().map(n => [3.0 * n.xyz[0] - 2.0 * n.xyz[1] + n.xyz[2]]),
      step=3,
      time=[0.75],
    ),
  ])
  let skin = source.extract_boundary().mesh(allow_loss=true)
  let constant = skin.integrate_surface_normal_field(0)
  for v in constant.normal_integral {
    qclose(v, 0.0)
  }
  let r = skin.integrate_surface_normal_field(1)
  // Existing authored map detJ=1+.2(u+v), V=11/60.
  // Integral(p*n)=V*grad(p) for the complete stored outward boundary.
  for i, slope in [3.0, -2.0, 1.0] {
    qclose(r.normal_integral[i], slope * 11.0 / 60.0)
  }
  assert_eq(r.time_step, 3)
  assert_eq(r.time, Some(0.75))
  assert_eq(r.elements, 4)
}

///|
test "scalar normal integral rejects invalid contracts and preserves protected cancellation" {
  let base = normal_graph()
  let scalar = integral_field(base, "NodeData", base.nodes().map(_ => [2.0]))
  let source = integral_with(base, [scalar])
  for frame in [-1, 1] {
    try source.integrate_surface_normal_field(frame) catch {
      _ => ()
    } noraise {
      _ => fail("bad field index accepted")
    }
  }
  for samples in [-1, 5, 9000001] {
    try source.integrate_surface_normal_field(0, max_samples=samples) catch {
      _ => ()
    } noraise {
      _ => fail("bad sample budget accepted")
    }
  }
  for components in [3, 9] {
    let field = integral_field(
      base,
      "NodeData",
      base.nodes().map(_ => Array::make(components, 1.0)),
    )
    let wrong = integral_with(base, [field])
    try wrong.integrate_surface_normal_field(0) catch {
      _ => ()
    } noraise {
      _ => fail("nonscalar field accepted")
    }
  }
  let partial = {
    ..scalar,
    integers: [7, 1, 5, 0],
    entries: scalar.entries[:5].to_owned(),
  }
  for field in [partial, { ..scalar, strings: ["pressure", "custom"], }] {
    let invalid = integral_with(base, [field])
    try invalid.integrate_surface_normal_field(0) catch {
      _ => ()
    } noraise {
      _ => fail("incomplete or named-scheme field accepted")
    }
  }
  let volume = flux_curved_volume()
  let unselected = integral_with(volume, [
    integral_field(volume, "NodeData", volume.nodes().map(_ => [1.0])),
  ])
  try unselected.integrate_surface_normal_field(0) catch {
    _ => ()
  } noraise {
    _ => fail("unselected volume accepted")
  }
  let huge = qmesh(2, [
    [0.0, 0.0, 0.0],
    [1.0e100, 0.0, 0.0],
    [0.0, 1.0e100, 0.0],
  ])
  let e = huge.elements()[0]
  let pair = @gmsh.mesh(
    huge.nodes(),
    [e, { ..e, tag: 702, nodes: [3, 2, 1], }],
    fields=[
      {
        location: "ElementData",
        strings: ["pressure"],
        reals: [],
        integers: [0, 1, 2],
        entries: [
          { tag: 201, values: [1.0e200], },
          { tag: 702, values: [1.0e200], },
        ],
      },
    ],
  )
  for v in pair.integrate_surface_normal_field(0).normal_integral {
    qclose(v, 0.0)
  }
  let overflow = integral_with(huge, [
    integral_field(huge, "ElementData", [[1.0e200]]),
  ])
  try overflow.integrate_surface_normal_field(0) catch {
    _ => ()
  } noraise {
    _ => fail("nonrepresentable vector component returned")
  }
  let tiny = qmesh(2, [
    [0.0, 0.0, 0.0],
    [1.0e-100, 0.0, 0.0],
    [0.0, 1.0e-100, 0.0],
  ])
  let underflow = integral_with(tiny, [
    integral_field(tiny, "ElementData", [[1.0e-200]]),
  ])
  try underflow.integrate_surface_normal_field(0) catch {
    _ => ()
  } noraise {
    _ => fail("nonzero vector component silently underflowed")
  }
  let zero = qmesh(2, [[0.0, 0.0, 0.0], [1.0, 0.0, 0.0], [2.0, 0.0, 0.0]])
  let z = integral_with(zero, [integral_field(zero, "ElementData", [[2.0]])]).integrate_surface_normal_field(
    0,
  )
  assert_eq(z.normal_integral, [0.0, 0.0, 0.0])
  assert_eq(z.zero_measure_samples, 6)
}
