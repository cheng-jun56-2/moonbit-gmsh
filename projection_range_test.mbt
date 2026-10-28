///|
/// Independent identities: signed area projection, affine maps and the exact
/// midpoint/center displacement. These regressions use the public MoonBit API.
test "max repair reference projection preserves representable small components" {
  let m = dr_fixture(9, [1.0e154, 1.0e154, 1.0])
  for sign in [1.0, -1.0] {
    for factor in [1.0, 0.5] {
      let r = m.sample_gauss_jacobians(201, reference_normal=[
        1.0e308 * factor,
        0.0,
        sign * 1.0e-308 * factor,
      ])
      assert_eq(r.nonpositive_samples, if sign > 0.0 { 0 } else { 3 })
      dr_relative(r.minimum_signed.unwrap(), sign * 1.0e-308)
      for s in r.samples {
        dr_relative(s.signed_jacobian.unwrap(), sign * 1.0e-308)
        dr_relative(s.measure, 1.0e308)
        dr_relative(s.scaled_jacobian, 1.0)
      }
    }
  }
  let orthogonal = m.sample_gauss_jacobians(201, reference_normal=[
    1.0, 0.0, 0.0,
  ])
  assert_eq(orthogonal.minimum_signed, Some(0.0))
  assert_eq(orthogonal.nonpositive_samples, 3)
  assert_eq(m.sample_gauss_jacobians(201).minimum_signed, None)
  // A real nonzero projection below the minimum subnormal is an error;
  // it must not be conflated with the true orthogonal zero above.
  try
    dr_fixture(9, [1.0, 1.0, 1.0]).sample_gauss_jacobians(201, reference_normal=[
      1.0e308, 0.0, 1.0e-308,
    ])
  catch {
    _ => ()
  } noraise {
    _ => fail("nonzero unrepresentable signed projection silently became zero")
  }
}

///|
test "max repair finite affine maps survive overflowing intermediate differences" {
  for
    (kind, scale, measure) in [
      (8, [1.7e308, 1.0, 1.0], 1.7e308),
      (10, [1.7e308, 1.0e-308, 1.0], 1.7),
      (16, [1.7e308, 1.0e-308, 1.0], 1.7),
      (12, [1.7e308, 1.0e-154, 1.0e-154], 1.7),
      (17, [1.7e308, 1.0e-154, 1.0e-154], 1.7),
    ] {
    let r = dr_fixture(kind, scale).sample_gauss_jacobians(201)
    assert_eq(r.nonpositive_samples, 0)
    for s in r.samples {
      dr_relative(s.measure, measure)
      dr_relative(s.scaled_jacobian, 1.0)
      for i in 0..<r.dimension {
        dr_relative(s.columns[i][i], scale[i])
        dr_relative(s.xyz[i], scale[i] * s.reference[i])
        for j in 0..<3 {
          if j != i {
            assert_eq(s.columns[i][j], 0.0)
          }
        }
      }
    }
  }
}

///|
test "max repair wide affine output has zero deviation and unit normals" {
  let (_, line) = dr_fixture(8, [1.7e308, 1.0, 1.0]).export_to_obj(
    @gmsh.PermissiveWithAudit,
  )
  assert_eq(line.estimated_chord_error, 0.0)
  assert_eq(line.output_vertices, 2)
  assert_eq(line.error_samples, 5)
  for kind in [10, 16] {
    let m = dr_fixture(kind, [1.7e308, 1.0e-308, 1.0])
    let (_, obj) = m.export_to_obj(@gmsh.PermissiveWithAudit)
    let (text, stl) = m.export_to_stl(@gmsh.PermissiveWithAudit)
    assert_eq(obj.estimated_chord_error, 0.0)
    assert_eq(stl.estimated_chord_error, 0.0)
    assert_eq(stl.output_elements, 2)
    assert_true(text.contains("facet normal 0 0 1"))
    assert_true(stl.losses.contains("curved_connectivity_linearized"))
    assert_true(!stl.losses.contains("degenerate_output_triangles"))
    try m.export_to_stl(@gmsh.Strict) catch {
      _ => ()
    } noraise {
      _ => fail("finite zero-deviation output still loses curved connectivity")
    }
  }
}

///|
test "max repair midpoint displacement survives an opposite large origin" {
  for offset in [1.0e-200, -1.0e-200] {
    let line = qmesh(8, [
      [-1.0e100, 0.0, 0.0],
      [1.0e100, 0.0, 0.0],
      [offset, 0.0, 0.0],
    ])
    let (_, loss) = line.export_to_obj(@gmsh.PermissiveWithAudit)
    dr_relative(loss.estimated_chord_error, offset.abs())
    let points = dr_fixture(10, [1.0e100, 1.0, 1.0]).nodes().map(n => n.xyz)
    points[8][0] = offset
    let quad = qmesh(10, points)
    let (_, loss) = quad.export_to_obj(@gmsh.PermissiveWithAudit)
    dr_relative(loss.estimated_chord_error, offset.abs())
  }
}
