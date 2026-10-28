///|
fn flux_reversed(m : @gmsh.Mesh) -> @gmsh.Mesh raise {
  let elements = m
    .elements()
    .map(e => {
      let order = match e.kind {
        2 => [0, 2, 1]
        3 => [0, 3, 2, 1]
        9 => [0, 2, 1, 5, 4, 3]
        16 => [0, 3, 2, 1, 7, 6, 5, 4]
        _ => [0, 3, 2, 1, 7, 6, 5, 4, 8]
      }
      { ..e, nodes: order.map(i => e.nodes[i]), }
    })
  @gmsh.mesh(m.nodes(), elements, fields=m.fields())
}

///|
fn flux_rotated(m : @gmsh.Mesh) -> @gmsh.Mesh raise {
  let elements = m
    .elements()
    .map(e => {
      let order = match e.kind {
        2 => [1, 2, 0]
        3 => [1, 2, 3, 0]
        9 => [1, 2, 0, 4, 5, 3]
        16 => [1, 2, 3, 0, 5, 6, 7, 4]
        _ => [1, 2, 3, 0, 5, 6, 7, 4, 8]
      }
      { ..e, nodes: order.map(i => e.nodes[i]), }
    })
  @gmsh.mesh(m.nodes(), elements, fields=m.fields())
}

///|
test "surface flux five families vector interpolation and stored reversal" {
  for kind in [2, 3, 9, 10, 16] {
    let base = integral_surface(kind)
    let field = integral_field(
      base,
      "NodeData",
      base
      .nodes()
      .map(n => [1.0 + n.xyz[0], 2.0 + n.xyz[1], 3.0 + n.xyz[0] * n.xyz[1]]),
    )
    let source = integral_with(base, [field])
    let forward = source.integrate_surface_flux(0)
    let back = flux_reversed(source).integrate_surface_flux(0)
    let expected = if kind == 2 {
      1.5
    } else if kind == 9 {
      1.5 + 1.0 / 24.0
    } else {
      12.0
    }
    qclose(forward.flux, expected)
    qclose(flux_rotated(source).integrate_surface_flux(0).flux, expected)
    qclose(back.flux, -expected)
    qclose(back.surface_measure, forward.surface_measure)
    qclose(
      forward.area_vector[2],
      if kind == 2 || kind == 9 {
        0.5
      } else {
        4.0
      },
    )
    assert_eq(forward.normal_convention, "stored_node_winding")
    assert_true(!forward.certified_error_bound)
    let cell = integral_field(base, "ElementData", [[1.0, -3.0, 2.0]])
    qclose(
      integral_with(base, [cell]).integrate_surface_flux(0).flux,
      if kind == 2 || kind == 9 {
        1.0
      } else {
        8.0
      },
    )
  }
}

///|
fn flux_curved_volume(fields? : Array[@gmsh.Field] = []) -> @gmsh.Mesh raise {
  let base = dr_fixture(11, [1.0, 1.0, 1.0])
  let nodes = base.nodes()
  nodes[4].xyz[2] = -0.05
  nodes[5].xyz[2] = -0.1
  nodes[6].xyz[2] = -0.05
  @gmsh.mesh(nodes, base.elements(), fields~)
}

///|
test "surface flux closed curved boundary obeys analytic divergence identities" {
  let base = flux_curved_volume()
  let position = integral_field(base, "NodeData", base.nodes().map(n => n.xyz))
  let constant = integral_field(
    base,
    "NodeData",
    base.nodes().map(_ => [1.0, 2.0, 3.0]),
  )
  let boundary = integral_with(base, [position, constant])
    .extract_boundary()
    .mesh(allow_loss=true)
  let r = boundary.integrate_surface_flux(0)
  // x=u,y=v,z=w-.2(u+v)+.2(u*u+v*v)+.2*w*(u+v).
  // detJ=1+.2(u+v), V=11/60; div(position)=3 gives flux11/20.
  qclose(r.flux, 11.0 / 20.0)
  for v in r.area_vector {
    qclose(v, 0.0)
  }
  qclose(boundary.integrate_surface_flux(1).flux, 0.0)
  assert_eq(r.elements, 4)
}

///|
test "surface flux exact frames physical selection compact tags and explicit face" {
  let base = flux_curved_volume()
  let fields = [
    integral_field(base, "NodeData", base.nodes().map(_ => [1.0])),
    integral_field(
      base,
      "NodeData",
      base.nodes().map(_ => [0.0, 0.0, -2.0]),
      step=0,
      time=[0.25],
    ),
    integral_field(
      base,
      "NodeData",
      base.nodes().map(_ => [0.0, 0.0, -4.0]),
      step=1,
      time=[0.5],
    ),
  ]
  let elements = base.elements()
  elements.push({
    tag: 700,
    kind: 9,
    nodes: [1, 3, 2, 7, 6, 5],
    entity: 0,
    physical: [44],
    extra: [],
  })
  let source = @gmsh.mesh(base.nodes(), elements, fields~)
  let boundary = source.extract_boundary()
  let wall = boundary.mesh(allow_loss=true).select_physical(2, 44)
  for index in [1, 2] {
    let r = wall.integrate_surface_flux(index)
    qclose(r.flux, index.to_double())
    qclose(wall.compact().integrate_surface_flux(index).flux, r.flux)
    qclose(flux_reversed(wall).integrate_surface_flux(index).flux, -r.flux)
    assert_eq(r.time, Some(if index == 1 { 0.25 } else { 0.5 }))
    assert_eq(r.time_step, index - 1)
  }
  let r = wall.integrate_surface_flux(1)
  qclose(r.area_vector[0], -1.0 / 30.0)
  qclose(r.area_vector[1], -1.0 / 30.0)
  qclose(r.area_vector[2], -0.5)
  assert_true(
    (wall.integrate_surface_field(1).integral[2].abs() - r.flux.abs()).abs() >
    0.01,
  )
}

///|
test "surface flux frame vector coverage scheme and budget failures are explicit" {
  let base = integral_surface(9)
  let vector = integral_field(
    base,
    "NodeData",
    base.nodes().map(_ => [0.0, 0.0, 2.0]),
  )
  let source = integral_with(base, [vector])
  for index in [-1, 1] {
    try source.integrate_surface_flux(index) catch {
      _ => ()
    } noraise {
      _ => fail("bad frame accepted")
    }
  }
  for count in [-1, 0, 5, 9000001] {
    try source.integrate_surface_flux(0, max_samples=count) catch {
      _ => ()
    } noraise {
      _ => fail("bad budget accepted")
    }
  }
  for values in [[1.0], [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0]] {
    let f = integral_field(base, "ElementData", [values])
    try integral_with(base, [f]).integrate_surface_flux(0) catch {
      _ => ()
    } noraise {
      _ => fail("nonvector flux accepted")
    }
  }
  let missing = {
    ..vector,
    entries: vector.entries[:5].to_owned(),
    integers: [0, 3, 5],
  }
  try integral_with(base, [missing]).integrate_surface_flux(0) catch {
    _ => ()
  } noraise {
    _ => fail("missing node data zero-filled")
  }
  let volume = dr_fixture(11, [1.0, 1.0, 1.0])
  let volume_data = integral_field(
    volume,
    "NodeData",
    volume.nodes().map(_ => [1.0, 2.0, 3.0]),
  )
  try integral_with(volume, [volume_data]).integrate_surface_flux(0) catch {
    _ => ()
  } noraise {
    _ => fail("volume silently integrated as a face")
  }
  let scheme = { ..vector, strings: ["velocity", "custom_scheme"], }
  try integral_with(base, [scheme]).integrate_surface_flux(0) catch {
    _ => ()
  } noraise {
    _ => fail("custom scheme silently ignored")
  }
}

///|
test "surface flux retains finite projection despite huge tangential components" {
  let base = qmesh(2, [
    [0.0, 0.0, 0.0],
    [1.0e154, 0.0, 0.0],
    [0.0, 1.0e154, 0.0],
  ])
  let vector = integral_field(
    base,
    "NodeData",
    base.nodes().map(_ => [1.0e308, 0.0, 1.0e-308]),
  )
  let source = integral_with(base, [vector])
  qclose(source.integrate_surface_flux(0).flux, 0.5)
  try source.integrate_surface_field(0) catch {
    _ => ()
  } noraise {
    _ => fail("nonrepresentable component integral should still error")
  }
  let zero = qmesh(2, [[0.0, 0.0, 0.0], [1.0, 0.0, 0.0], [2.0, 0.0, 0.0]])
  let r = integral_with(zero, [
    integral_field(zero, "ElementData", [[1.0, 2.0, 3.0]]),
  ]).integrate_surface_flux(0)
  assert_eq(r.flux, 0.0)
  assert_eq(r.zero_measure_samples, 6)
  let tiny = qmesh(2, [
    [0.0, 0.0, 0.0],
    [1.0e-100, 0.0, 0.0],
    [0.0, 1.0e-100, 0.0],
  ])
  try
    integral_with(tiny, [
      integral_field(tiny, "ElementData", [[0.0, 0.0, 1.0e-200]]),
    ]).integrate_surface_flux(0)
  catch {
    _ => ()
  } noraise {
    _ => fail("nonzero flux underflow silently zero-filled")
  }
  let quad = integral_surface(3)
  try
    integral_with(quad, [
      integral_field(quad, "ElementData", [[0.0, 0.0, 1.0e308]]),
    ]).integrate_surface_flux(0)
  catch {
    _ => ()
  } noraise {
    _ => fail("nonrepresentable flux returned")
  }
}
