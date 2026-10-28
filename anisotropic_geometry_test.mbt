///|
test "finite anisotropic volume and orientation survive intermediate underflow" {
  let ns : Array[@gmsh.Node] = [
    { tag: 1, xyz: [0.0, 0.0, 0.0], dim: -1, entity: 0, parameters: [], },
    { tag: 2, xyz: [1.0e150, 0.0, 0.0], dim: -1, entity: 0, parameters: [], },
    { tag: 3, xyz: [0.0, 1.0e-50, 0.0], dim: -1, entity: 0, parameters: [], },
    { tag: 4, xyz: [0.0, 0.0, 1.0e-50], dim: -1, entity: 0, parameters: [], },
  ]
  let cell : @gmsh.Element = {
    tag: 1,
    kind: 4,
    nodes: [1, 2, 3, 4],
    entity: 0,
    physical: [],
    extra: [],
  }
  let q = @gmsh.mesh(ns, [cell]).quality(1)
  assert_true((q.signed_volume / (1.0e50 / 6.0) - 1.0).abs() < 1.0e-14)
  assert_true(q.quality > 0.0)
  assert_true(!q.inverted)
  let flipped = @gmsh.mesh(ns, [{ ..cell, nodes: [1, 3, 2, 4], }]).quality(1)
  assert_true(flipped.inverted)
  assert_true((flipped.signed_volume / q.signed_volume + 1.0).abs() < 1.0e-14)
}

///|
test "small component in a long edge still contributes finite triangle area" {
  let ns : Array[@gmsh.Node] = [
    { tag: 1, xyz: [0.0, 0.0, 0.0], dim: -1, entity: 0, parameters: [], },
    {
      tag: 2,
      xyz: [1.0e100, 1.0e-210, 0.0],
      dim: -1,
      entity: 0,
      parameters: [],
    },
    { tag: 3, xyz: [1.0e100, 0.0, 0.0], dim: -1, entity: 0, parameters: [], },
  ]
  let m = @gmsh.mesh(ns, [
    { tag: 1, kind: 2, nodes: [1, 2, 3], entity: 0, physical: [], extra: [], },
  ])
  let q = m.quality(1)
  assert_true((q.measure / 5.0e-111 - 1.0).abs() < 1.0e-14)
  assert_true(q.quality > 0.0)
}
