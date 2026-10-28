///|
test "subset and compact track sparse field indices" {
  let m = triangle()
  let n = m.subset([77]).compact()
  assert_eq(n.es[0].nodes, [1, 2, 3])
  assert_eq(n.fs[0].entries.map(d => d.tag), [1, 3])
  assert_eq(n.fs[0].entries[1].values, [310.0])
  assert_eq(n.subset([]).fs[0].integers[2], 0)
}

///|
test "shared-face adjacency and outward tetra boundary" {
  let ns : Array[Node] = [
    { tag: 1, xyz: [0.0, 0.0, 0.0], dim: -1, entity: 0, parameters: [], },
    { tag: 2, xyz: [1.0, 0.0, 0.0], dim: -1, entity: 0, parameters: [], },
    { tag: 3, xyz: [0.0, 1.0, 0.0], dim: -1, entity: 0, parameters: [], },
    { tag: 4, xyz: [0.0, 0.0, 1.0], dim: -1, entity: 0, parameters: [], },
    { tag: 5, xyz: [0.0, 0.0, -1.0], dim: -1, entity: 0, parameters: [], },
  ]
  let m = mesh(ns, [
    {
      tag: 10,
      kind: 4,
      nodes: [1, 2, 3, 4],
      entity: 0,
      physical: [],
      extra: [],
    },
    {
      tag: 20,
      kind: 4,
      nodes: [1, 3, 2, 5],
      entity: 0,
      physical: [],
      extra: [],
    },
  ])
  let t = m.topology()
  assert_eq(t.facets.length(), 7)
  assert_eq(t.boundary.length(), 6)
  assert_eq(t.facets.filter(f => f.owners.length() == 2)[0].owners, [10, 20])
  assert_eq(m.components(), [[10, 20]])
  let q = m.quality(10)
  assert_true((q.measure - 1.0 / 6.0).abs() < 1.0e-15)
  assert_true(!q.inverted)
  let flipped = mesh(ns, [{ ..m.es[0], nodes: [1, 3, 2, 4], }])
  assert_true(flipped.quality(10).inverted)
  assert_eq(m.obj().split("\n").filter(s => s.has_prefix("f ")).length(), 6)
}

///|
test "duplicate isolated degenerate and unsupported geometry" {
  let m = triangle()
  let ns = m.nodes()
  ns.push({ ..ns[0], tag: 100, })
  let n = mesh(ns, [{ ..m.es[0], nodes: [10, 10, 33], }])
  let d = n.diagnostics()
  assert_eq(d.duplicate_nodes, [[10, 100]])
  assert_eq(d.isolated, [90, 100])
  assert_eq(d.repeated_connectivity, [77])
  assert_true(d.qualities[0].degenerate)
  assert_true(
    try {
      ignore(n.topology())
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(m.vtk())
      false
    } catch {
      _ => true
    },
  )
  assert_true(m.vtk(allow_loss=true).contains("3 0 1 2"))
}

///|
test "regular simplex quality and numerical range" {
  let h = 3.0.sqrt() / 2.0
  let ns : Array[Node] = [
    { tag: 1, xyz: [0.0, 0.0, 0.0], dim: -1, entity: 0, parameters: [], },
    { tag: 2, xyz: [1.0, 0.0, 0.0], dim: -1, entity: 0, parameters: [], },
    { tag: 3, xyz: [0.5, h, 0.0], dim: -1, entity: 0, parameters: [], },
    {
      tag: 4,
      xyz: [0.5, h / 3.0, (2.0 / 3.0).sqrt()],
      dim: -1,
      entity: 0,
      parameters: [],
    },
  ]
  let es : Array[Element] = [
    { tag: 1, kind: 2, nodes: [1, 2, 3], entity: 0, physical: [], extra: [], },
    {
      tag: 2,
      kind: 4,
      nodes: [1, 2, 3, 4],
      entity: 0,
      physical: [],
      extra: [],
    },
  ]
  let m = mesh(ns, es)
  assert_true((m.quality(1).quality - 1.0).abs() < 1.0e-14)
  assert_true((m.quality(2).quality - 1.0).abs() < 1.0e-14)
  let huge = mesh(ns.map(n => { ..n, xyz: n.xyz.map(x => x * 1.0e200), }), es)
  assert_true(
    try {
      ignore(huge.quality(1))
      false
    } catch {
      _ => true
    },
  )
}
