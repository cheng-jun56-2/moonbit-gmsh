///|
fn nodes() -> Array[@gmsh.Node] {
  [
    [0.0, 0.0, 0.0],
    [1.0, 0.0, 0.0],
    [0.0, 1.0, 0.0],
    [0.0, 0.0, 1.0],
    [0.0, 0.0, -1.0],
  ].mapi((i, xyz) => {
    tag: (i + 1) * 10,
    xyz,
    dim: -1,
    entity: 0,
    parameters: [],
  })
}

///|
fn cell(tag : Int, kind : Int, ns : Array[Int]) -> @gmsh.Element {
  { tag, kind, nodes: ns, entity: 0, physical: [], extra: [], }
}

///|
test "boundary coverage never inherits volume groups or approves lossy export" {
  let b = @gmsh.mesh(nodes(), [
    { ..cell(90, 2, [10, 20, 30]), physical: [9], },
    { ..cell(77, 1, [20, 10]), physical: [4, 5], },
  ]).extract_boundary()
  let c = b.coverage(required_groups=[9, 4, 7])
  assert_eq(c.facets, 3)
  assert_eq(c.unlabeled.length(), 2)
  assert_eq(c.multiple.map(f => f.explicit_element), [77])
  assert_eq(c.missing_groups, [7, 9])
  assert_eq(c.groups.map(g => g.tag), [4, 5])
  assert_eq(c.groups.map(g => g.facets), [1, 1])
  assert_true(c.unlabeled.all(f => f.owner == 90 && f.explicit_element == 0))
  c.unlabeled.clear()
  assert_eq(b.coverage().unlabeled.length(), 2)
  try b.mesh() catch {
    _ => ()
  } noraise {
    _ => fail("coverage inspection must not waive export losses")
  }
  for required in [[0], [-1], [4, 4]] {
    try b.coverage(required_groups=required) catch {
      _ => ()
    } noraise {
      _ => fail("invalid coverage contract must be rejected")
    }
  }
}

///|
test "shared quadrilateral faces require matching edges not just node sets" {
  let ns = [
    [0.0, 0.0, 0.0],
    [1.0, 0.0, 0.0],
    [1.0, 1.0, 0.0],
    [0.0, 1.0, 0.0],
    [0.5, 0.5, 1.0],
    [0.5, 0.5, -1.0],
  ].mapi((i, xyz) => @gmsh.Node::{
    tag: i + 1,
    xyz,
    dim: -1,
    entity: 0,
    parameters: [],
  })
  for base in [[1, 2, 3, 4], [3, 4, 1, 2], [1, 4, 3, 2]] {
    let lower = base.copy()
    lower.push(6)
    let m = @gmsh.mesh(ns, [cell(10, 7, [1, 2, 3, 4, 5]), cell(20, 7, lower)])
    assert_eq(m.topology().boundary.length(), 8)
    assert_eq(m.extract_boundary().mesh().elements().length(), 8)
  }
  let crossed = @gmsh.mesh(ns, [
    cell(10, 7, [1, 2, 3, 4, 5]),
    cell(20, 7, [1, 3, 2, 4, 6]),
  ])
  try crossed.topology() catch {
    _ => ()
  } noraise {
    _ => fail("different polygon edges must not form an internal face")
  }
  try crossed.extract_boundary() catch {
    _ => ()
  } noraise {
    _ => fail("incompatible shared face must not disappear from the boundary")
  }
  try crossed.obj() catch {
    _ => ()
  } noraise {
    _ => fail("OBJ must not export the incorrect outer surface")
  }
}

///|
test "boundary removes shared faces and retains sparse source identity" {
  let m = @gmsh.mesh(nodes(), [
    cell(2147483647, 4, [10, 20, 30, 40]),
    cell(1, 4, [10, 30, 20, 50]),
  ])
  let b = m.extract_boundary()
  let report = b.report()
  let out = b.mesh()
  assert_eq(out.elements().length(), 6)
  assert_eq(out.elements().map(e => e.tag), [2, 3, 4, 5, 6, 7])
  assert_eq(out.nodes().map(n => n.tag), [10, 20, 30, 40, 50])
  assert_eq(report.facets.map(f => f.owner), [
    2147483647, 2147483647, 2147483647, 1, 1, 1,
  ])
  assert_eq(report.facets.map(f => f.local_facet), [1, 2, 3, 1, 2, 3])
  assert_true(out.elements().all(e => e.nodes != [10, 30, 20]))
  report.facets.clear()
  assert_eq(b.report().facets.length(), 6)
  assert_eq(m.elements().length(), 2)
  assert_eq(@gmsh.decode(out.encode()).elements().length(), 6)
}

///|
test "explicit facets retain winding labels and sparse data with loss gate" {
  let edge = { ..cell(77, 1, [20, 10]), entity: 7, physical: [4], extra: [0], }
  let m = @gmsh.mesh(
    nodes(),
    [cell(90, 2, [10, 20, 30]), edge],
    names=[{ dim: 1, tag: 4, name: "wall", }],
    fields=[
      {
        location: "ElementData",
        strings: ["density"],
        reals: [1.5],
        integers: [3, 1, 2, 9],
        entries: [{ tag: 90, values: [100.0], }, { tag: 77, values: [3.0], }],
      },
      {
        location: "NodeData",
        strings: ["temperature"],
        reals: [0.0],
        integers: [0, 1, 2],
        entries: [{ tag: 10, values: [5.0], }, { tag: 50, values: [9.0], }],
      },
    ],
  )
  let b = m.extract_boundary()
  try b.mesh() catch {
    _ => ()
  } noraise {
    _ => fail("lost fields must require permission")
  }
  let out = b.mesh(allow_loss=true)
  assert_eq(out.elements()[0].nodes, [20, 10])
  assert_eq(out.elements()[0].tag, 77)
  assert_eq(out.elements()[0].physical, [4])
  assert_eq(out.elements()[0].extra, [0])
  assert_eq(b.report().facets[0].explicit_element, 77)
  assert_eq(out.fields()[0].integers, [3, 1, 1, 9])
  assert_eq(out.fields()[0].entries[0].values, [3.0])
  assert_eq(out.fields()[1].entries[0].tag, 10)
  assert_eq(b.report().fields[0].retained_entries, 1)
  assert_eq(out.physical_names()[0].name, "wall")
  assert_eq(out.elements()[1].physical, [])
}

///|
test "closed chains have empty boundary and budgets never truncate" {
  let m = @gmsh.mesh(nodes(), [
    cell(1, 1, [10, 20]),
    cell(2, 1, [20, 30]),
    cell(3, 1, [30, 10]),
  ])
  assert_eq(m.extract_boundary(max_facets=0).mesh().elements().length(), 0)
  let open = m.subset([1, 2])
  assert_eq(open.extract_boundary().mesh().elements().map(e => e.nodes), [
    [10],
    [30],
  ])
  try open.extract_boundary(max_facets=1) catch {
    _ => ()
  } noraise {
    _ => fail("budget must reject")
  }
  try m.extract_boundary(dimension=3) catch {
    _ => ()
  } noraise {
    _ => fail("missing dimension must reject")
  }
  try m.extract_boundary(dimension=0) catch {
    _ => ()
  } noraise {
    _ => fail("point boundary undefined")
  }
}

///|
test "ambiguous and nonmanifold boundary inputs are rejected" {
  let ns = nodes()
  let cases : Array[Array[@gmsh.Element]] = [
    [cell(1, 1, [10, 20]), cell(2, 1, [20, 10])],
    [cell(1, 1, [10, 10])],
    [cell(1, 1, [10, 20]), cell(2, 1, [10, 30]), cell(3, 1, [10, 40])],
    [cell(1, 2, [10, 20, 30]), cell(2, 1, [10, 20]), cell(3, 1, [20, 10])],
    [cell(1, 2, [10, 20, 30]), cell(2, 8, [10, 20, 40])],
  ]
  for es in cases {
    try @gmsh.mesh(ns, es).extract_boundary() catch {
      _ => ()
    } noraise {
      _ => fail("ambiguous/incompatible mesh accepted")
    }
  }
}

///|
test "entity context cannot silently become a lower dimensional CAD model" {
  let ns = nodes().map(n => { ..n, dim: 3, entity: 7, })
  let m = @gmsh.mesh(
    ns,
    [{ ..cell(5, 4, [10, 20, 30, 40]), entity: 7, physical: [4], }],
    entities=[
      {
        dim: 3,
        tag: 7,
        bounds: [0.0, 0.0, -1.0, 1.0, 1.0, 1.0],
        physical: [4],
        boundary: [],
      },
    ],
    names=[{ dim: 3, tag: 4, name: "volume", }],
    version="4.1",
  )
  let b = m.extract_boundary()
  assert_true(
    b.report().losses.contains("entity_graph_and_node_classification"),
  )
  assert_true(
    b.report().losses.contains("excluded_element_labels_not_inherited"),
  )
  try b.mesh() catch {
    _ => ()
  } noraise {
    _ => fail("classification loss accepted")
  }
  let out = b.mesh(allow_loss=true)
  assert_eq(out.entities().length(), 0)
  assert_true(out.nodes().all(n => n.dim == -1 && n.parameters.is_empty()))
  assert_true(out.elements().all(e => e.physical.is_empty() && e.entity == 0))
  assert_eq(m.entities()[0].dim, 3)
}

///|
test "opaque sections require separate explicit removal" {
  let m = @gmsh.mesh(nodes(), [cell(1, 2, [10, 20, 30])], unknown=[
    { name: "Comments", body: "opaque tags", },
  ])
  try m.extract_boundary() catch {
    _ => ()
  } noraise {
    _ => fail("opaque references accepted")
  }
  assert_eq(
    m.without_unknown().extract_boundary().mesh().elements().length(),
    3,
  )
}
