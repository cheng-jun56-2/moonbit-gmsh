///|
test "linear range repair wide triangle has finite subnormal quality" {
  for
    points in [
      [[-1.7e308, 0.0, 0.0], [1.7e308, 0.0, 0.0], [-1.7e308, 1.0, 0.0]],
      [[-1.7e308, 0.0, 0.0], [-1.7e308, 1.0, 0.0], [1.7e308, 0.0, 0.0]],
      [[0.0, -1.7e308, 0.0], [0.0, 1.7e308, 0.0], [0.0, -1.7e308, 1.0]],
    ] {
    let m = qmesh(2, points)
    let q = m.quality(201, tolerance=0.0)
    dr_relative(q.measure, 1.7e308)
    // 1100-digit Decimal on the exact binary64 fixture inputs:
    // 4*sqrt(3)*A / sum of the three squared edge lengths.
    dr_relative(q.quality, 5.094267081084936e-309)
    assert_true(!q.degenerate && !q.inverted)
    assert_eq(q.signed_volume, 0.0)
    assert_true(m.quality(201).degenerate)
  }
}

///|
test "linear range repair collapsed geometry stays diagnosable and range errors explicit" {
  for
    (kind, points) in [
      (2, [[-1.7e308, 0.0, 0.0], [1.7e308, 0.0, 0.0], [0.0, 0.0, 0.0]]),
      (
        4,
        [
          [-1.7e308, 0.0, 0.0],
          [1.7e308, 0.0, 0.0],
          [0.0, 0.0, 0.0],
          [1.0, 0.0, 0.0],
        ],
      ),
      (2, [[1.7e308, 0.0, 0.0], [1.7e308, 0.0, 0.0], [1.7e308, 0.0, 0.0]]),
    ] {
    let m = qmesh(kind, points)
    let q = m.quality(201, tolerance=0.0)
    assert_eq(q.measure, 0.0)
    assert_eq(q.quality, 0.0)
    assert_true(q.degenerate && !q.inverted)
    assert_true(m.diagnostics().qualities[0].degenerate)
  }
  let area_overflow = qmesh(2, [
    [-1.7e308, 0.0, 0.0],
    [1.7e308, 0.0, 0.0],
    [-1.7e308, 2.0, 0.0],
  ])
  try area_overflow.quality(201) catch {
    _ => ()
  } noraise {
    _ => fail("nonrepresentable area returned")
  }
  let quality_underflow = qmesh(4, [
    [-1.7e308, 0.0, 0.0],
    [1.7e308, 0.0, 0.0],
    [-1.7e308, 1.0, 0.0],
    [-1.7e308, 0.0, 1.0],
  ])
  try quality_underflow.quality(201) catch {
    _ => ()
  } noraise {
    _ => fail("nonzero unrepresentable quality silently became zero")
  }
}
