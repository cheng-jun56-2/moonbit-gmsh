///|
/// Regressions for concrete public-path failures reproduced in deep-repair05.
/// Expectations are diagonal determinant/area, axis normal, or exact sampled
/// bubble-height identities; they are not copies of the implementation.
fn dr_fixture(kind : Int, scale : Array[Double]) -> @gmsh.Mesh raise {
  let refs : Array[Array[Double]] = match kind {
    8 => [[-1.0, 0, 0], [1.0, 0, 0], [0.0, 0, 0]]
    9 =>
      [
        [0.0, 0.0, 0],
        [1.0, 0.0, 0],
        [0.0, 1.0, 0],
        [0.5, 0.0, 0],
        [0.5, 0.5, 0],
        [0.0, 0.5, 0],
      ]
    10 =>
      [
        [-1.0, -1.0, 0],
        [1.0, -1.0, 0],
        [1.0, 1.0, 0],
        [-1.0, 1.0, 0],
        [0.0, -1.0, 0],
        [1.0, 0.0, 0],
        [0.0, 1.0, 0],
        [-1.0, 0.0, 0],
        [0.0, 0.0, 0],
      ]
    11 =>
      [
        [0.0, 0.0, 0.0],
        [1.0, 0.0, 0.0],
        [0.0, 1.0, 0.0],
        [0.0, 0.0, 1.0],
        [0.5, 0.0, 0.0],
        [0.5, 0.5, 0.0],
        [0.0, 0.5, 0.0],
        [0.0, 0.0, 0.5],
        [0.0, 0.5, 0.5],
        [0.5, 0.0, 0.5],
      ]
    12 =>
      [
        [-1.0, -1.0, -1.0],
        [1.0, -1.0, -1.0],
        [1.0, 1.0, -1.0],
        [-1.0, 1.0, -1.0],
        [-1.0, -1.0, 1.0],
        [1.0, -1.0, 1.0],
        [1.0, 1.0, 1.0],
        [-1.0, 1.0, 1.0],
        [0.0, -1.0, -1.0],
        [-1.0, 0.0, -1.0],
        [-1.0, -1.0, 0.0],
        [1.0, 0.0, -1.0],
        [1.0, -1.0, 0.0],
        [0.0, 1.0, -1.0],
        [1.0, 1.0, 0.0],
        [-1.0, 1.0, 0.0],
        [0.0, -1.0, 1.0],
        [-1.0, 0.0, 1.0],
        [1.0, 0.0, 1.0],
        [0.0, 1.0, 1.0],
        [0.0, 0.0, -1.0],
        [0.0, -1.0, 0.0],
        [-1.0, 0.0, 0.0],
        [1.0, 0.0, 0.0],
        [0.0, 1.0, 0.0],
        [0.0, 0.0, 1.0],
        [0.0, 0.0, 0.0],
      ]
    16 =>
      [
        [-1.0, -1.0, 0],
        [1.0, -1.0, 0],
        [1.0, 1.0, 0],
        [-1.0, 1.0, 0],
        [0.0, -1.0, 0],
        [1.0, 0.0, 0],
        [0.0, 1.0, 0],
        [-1.0, 0.0, 0],
      ]
    17 =>
      [
        [-1.0, -1.0, -1.0],
        [1.0, -1.0, -1.0],
        [1.0, 1.0, -1.0],
        [-1.0, 1.0, -1.0],
        [-1.0, -1.0, 1.0],
        [1.0, -1.0, 1.0],
        [1.0, 1.0, 1.0],
        [-1.0, 1.0, 1.0],
        [0.0, -1.0, -1.0],
        [-1.0, 0.0, -1.0],
        [-1.0, -1.0, 0.0],
        [1.0, 0.0, -1.0],
        [1.0, -1.0, 0.0],
        [0.0, 1.0, -1.0],
        [1.0, 1.0, 0.0],
        [-1.0, 1.0, 0.0],
        [0.0, -1.0, 1.0],
        [-1.0, 0.0, 1.0],
        [1.0, 0.0, 1.0],
        [0.0, 1.0, 1.0],
      ]
    _ => fail("unsupported fixture")
  }
  qmesh(kind, refs.map(p => p.mapi((i, x) => x * scale[i])))
}

///|
fn dr_relative(actual : Double, expected : Double) -> Unit raise {
  assert_true((actual / expected - 1.0).abs() < 1.0e-12)
}

///|
test "deep repair anisotropic affine Jacobians retain nonzero measure" {
  for
    (kind, scale, expected) in [
      (9, [1.0, 1.0e-200, 1.0], 1.0e-200),
      (9, [1.0e100, 1.0e-100, 1.0], 1.0),
      (10, [1.0e100, 1.0e-100, 1.0], 1.0),
      (11, [1.0e200, 1.0e-100, 1.0e-100], 1.0),
      (12, [1.0e100, 1.0e-100, 1.0e-100], 1.0e-100),
      (17, [1.0e100, 1.0e-100, 1.0e-100], 1.0e-100),
    ] {
    let report = dr_fixture(kind, scale).sample_gauss_jacobians(201)
    assert_eq(report.nonpositive_samples, 0)
    assert_true(!report.globally_certified)
    for sample in report.samples {
      dr_relative(sample.measure, expected)
      dr_relative(sample.scaled_jacobian, 1.0)
      assert_eq(sample.normal, [0.0, 0.0, 1.0])
    }
  }
}

///|
test "deep repair nonzero underflow rejects but true collapse stays zero" {
  try
    dr_fixture(11, [1.0, 1.0e-200, 1.0e-200]).sample_gauss_jacobians(201)
  catch {
    _ => ()
  } noraise {
    _ => fail("nonzero1e-400 silently rounded to a degenerate zero")
  }
  let collapsed = dr_fixture(11, [0.0, 0.0, 0.0]).sample_gauss_jacobians(201)
  assert_eq(collapsed.minimum_measure, 0.0)
  assert_eq(collapsed.nonpositive_samples, 4)
  let inverted = dr_fixture(11, [-1.0, 1.0, 1.0]).sample_gauss_jacobians(201)
  assert_eq(inverted.nonpositive_samples, 4)
  dr_relative(inverted.minimum_signed.unwrap(), -1.0)
}

///|
test "deep repair corner metrics do not erase a thin tetrahedral angle" {
  let report = dr_fixture(11, [1.0, 1.0, 1.0e-200]).sample_gauss_jacobians(201)
  dr_relative(report.corner_edge_ratio.unwrap(), 1.4142135623730951e200)
  // atan(sqrt(2)*1.0e-200)*180/PI; the cubic correction is unrepresentable.
  dr_relative(
    report.corner_minimum_dihedral_degrees.unwrap(),
    8.102846845413955e-199,
  )
  for p in report.samples {
    dr_relative(p.scaled_jacobian, 1.0)
  }
}

///|
test "deep repair strict OBJ and STL unit normals survive finite scale extremes" {
  for scale in [1.0e-100, 1.0e100, 1.0e-200] {
    let m = qmesh(2, [[0.0, 0.0, 0.0], [scale, 0.0, 0.0], [0.0, scale, 0.0]])
    let (_, obj) = m.export_to_obj(@gmsh.Strict)
    assert_eq(obj.losses, [])
    let (text, stl) = m.export_to_stl(@gmsh.Strict)
    assert_true(text.contains("facet normal 0 0 1"))
    assert_eq(stl.losses, [])
  }
  let huge = qmesh(2, [
    [-1.0e308, 0.0, 0.0],
    [1.0e308, 0.0, 0.0],
    [-1.0e308, 1.0, 0.0],
  ])
  let (text, _) = huge.export_to_stl(@gmsh.Strict)
  assert_true(text.contains("facet normal 0 0 1"))
}

///|
test "deep repair sampled planar deviation preserves small curvature" {
  for height in [1.0e-200, 1.0e200] {
    let base = dr_fixture(10, [1.0, 1.0, 1.0])
    let points = base.nodes().map(n => n.xyz)
    points[8][2] = height
    let (_, report) = qmesh(10, points).export_to_obj(@gmsh.PermissiveWithAudit)
    dr_relative(report.estimated_chord_error, height)
    let linear = [points[0], points[1], [1.0, 1.0, height], points[3]]
    let (_, quad) = qmesh(3, linear).export_to_obj(@gmsh.PermissiveWithAudit)
    dr_relative(quad.estimated_chord_error, height / 6.0)
  }
}

///|
test "deep repair retained midside vertices are not falsely discarded" {
  let base = dr_fixture(9, [1.0, 1.0, 1.0])
  let xyz = base.nodes().map(n => n.xyz)
  for
    p in [
      [0.5, 0.0, -1.0],
      [0.5, -1.0, -1.0],
      [0.5, 0.5, 1.0],
      [1.5, 0.5, 1.0],
      [-1.0, 0.5, 0.0],
      [-1.0, 0.5, 1.0],
    ] {
    xyz.push(p)
  }
  let ns = xyz.mapi((i, p) => @gmsh.Node::{
    tag: i + 1,
    xyz: p,
    dim: -1,
    entity: 0,
    parameters: [],
  })
  let cells = base.elements()
  cells.push({
    tag: 202,
    kind: 2,
    nodes: [4, 7, 8],
    entity: 0,
    physical: [],
    extra: [],
  })
  let (_, partial) = @gmsh.mesh(ns, cells).export_to_obj(
    @gmsh.PermissiveWithAudit,
  )
  assert_eq(partial.discarded_curved_node_tags, [5, 6])
  cells.push({
    tag: 203,
    kind: 2,
    nodes: [5, 9, 10],
    entity: 0,
    physical: [],
    extra: [],
  })
  cells.push({
    tag: 204,
    kind: 2,
    nodes: [6, 11, 12],
    entity: 0,
    physical: [],
    extra: [],
  })
  let m = @gmsh.mesh(ns, cells)
  let (_, all) = m.export_to_obj(@gmsh.PermissiveWithAudit)
  assert_eq(all.discarded_curved_node_tags, [])
  assert_true(all.losses.contains("curved_connectivity_linearized"))
  try m.export_to_obj(@gmsh.Strict) catch {
    _ => ()
  } noraise {
    _ => fail("retained vertices must not waive interpolation loss")
  }
}

///|
test "deep repair center normals remain unit and outward at small scales" {
  for scale in [1.0e-100, 1.0e100, 1.0e-200] {
    let m = dr_fixture(11, [scale, scale, scale])
    for o in m.extract_boundary().orientation_report() {
      assert_eq(o.status, "outward_at_center")
      dr_relative(o.center_normal.fold(init=0.0, fn(a, v) { a + v * v }), 1.0)
    }
    let elements = m.elements()
    elements.push({
      tag: 700,
      kind: 9,
      nodes: [1, 2, 3, 5, 6, 7],
      entity: 0,
      physical: [44],
      extra: [],
    })
    let reversed = @gmsh.mesh(m.nodes(), elements).extract_boundary()
    assert_true(reversed.orientation_report()[0].explicit_reversed)
    assert_eq(reversed.orientation_report()[0].status, "inward_at_center")
  }
}
