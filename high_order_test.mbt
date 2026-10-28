///|
test "quadratic explicit boundary labels fields and direction survive" {
  let m = qmesh(11, [
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
  ])
  let explicit : @gmsh.Element = {
    tag: 700,
    kind: 9,
    nodes: [1, 2, 3, 5, 6, 7],
    entity: 9,
    physical: [44, 45],
    extra: [0],
  }
  let es = m.elements()
  es.push(explicit)
  let input = @gmsh.mesh(m.nodes(), es, fields=[
    {
      location: "ElementData",
      strings: ["flux"],
      reals: [0.25],
      integers: [0, 1, 1],
      entries: [{ tag: 700, values: [9.0], }],
    },
  ])
  let b = input.extract_boundary()
  let output = b.mesh()
  assert_eq(
    output.elements()[0].to_json().stringify(),
    explicit.to_json().stringify(),
  )
  assert_eq(output.fields()[0].entries[0].tag, 700)
  assert_eq(output.fields()[0].entries[0].values, [9.0])
  let c = b.coverage(required_groups=[44, 45])
  assert_eq(c.groups.map(g => g.tag), [44, 45])
  assert_eq(c.multiple.length(), 1)
  let orientations = b.orientation_report()
  assert_true(orientations[0].explicit_reversed)
  assert_eq(orientations[0].status, "inward_at_center")
  orientations[0].center_normal.clear()
  assert_eq(b.orientation_report()[0].center_normal.length(), 3)
}

///|
test "Quad9 face center loss cannot disappear behind zero edge sag" {
  let m = qmesh(10, [
    [-1.0, -1.0, 0.0],
    [1.0, -1.0, 0.0],
    [1.0, 1.0, 0.0],
    [-1.0, 1.0, 0.0],
    [0.0, -1.0, 0.0],
    [1.0, 0.0, 0.0],
    [0.0, 1.0, 0.0],
    [-1.0, 0.0, 0.0],
    [0.0, 0.0, 0.1],
  ])
  try m.export_to_obj(@gmsh.Strict) catch {
    _ => ()
  } noraise {
    _ => fail("strict export accepted curved loss")
  }
  let (_, report) = m.export_to_obj(@gmsh.PermissiveWithAudit)
  qclose(report.estimated_chord_error, 0.1)
  assert_eq(report.discarded_curved_node_tags, [5, 6, 7, 8, 9])
  assert_eq(report.output_elements, 2)
  assert_true(!report.certified_bound)
  let (stl, loss) = m.export_to_stl(@gmsh.PermissiveWithAudit)
  assert_true(stl.contains("facet normal"))
  assert_eq(loss.output_elements, 2)
}

///|
test "sampled positive Tet10 remains explicitly uncertified" {
  let m = qmesh(11, [
    [0.0, 0.0, 0.0],
    [1.0, 0.0, 0.0],
    [0.0, 1.0, 0.0],
    [0.0, 0.0, 0.25],
    [0.5, 0.0, 0.0],
    [0.5, 0.5, 0.0],
    [0.0, 0.5, 0.0],
    [0.0, 0.0, 0.3125],
    [0.0, 0.5, 0.3125],
    [0.5, 0.0, 0.3125],
  ])
  let report = m.sample_gauss_jacobians(201)
  assert_eq(report.nonpositive_samples, 0)
  assert_true(!report.globally_certified)
  qclose(report.minimum_signed.unwrap(), 0.12188470506254723)
}

///|
test "high-order mismatch budget invalid normal and numeric range refuse" {
  let m = qmesh(9, [
    [0.0, 0.0, 0.0],
    [1.0, 0.0, 0.0],
    [0.0, 1.0, 0.0],
    [0.5, 0.0, 0.0],
    [0.5, 0.5, 0.0],
    [0.0, 0.5, 0.0],
  ])
  try m.extract_boundary(max_facets=2) catch {
    _ => ()
  } noraise {
    _ => fail("budget")
  }
  try m.sample_gauss_jacobians(201, reference_normal=[0.0, 0.0, 0.0]) catch {
    _ => ()
  } noraise {
    _ => fail("zero normal")
  }
  try m.sample_gauss_jacobians(999) catch {
    _ => ()
  } noraise {
    _ => fail("unknown tag")
  }
  let normal = m.sample_gauss_jacobians(201, reference_normal=[
    0.0, 0.0, 1.0e300,
  ])
  qclose(normal.minimum_signed.unwrap(), 1.0)
  let es = m.elements()
  es.push({
    tag: 700,
    kind: 8,
    nodes: [1, 2, 6],
    entity: 0,
    physical: [],
    extra: [],
  })
  try @gmsh.mesh(m.nodes(), es).extract_boundary() catch {
    _ => ()
  } noraise {
    _ => fail("mismatched midside node")
  }
  let huge = qmesh(9, m.nodes().map(n => n.xyz.map(x => x * 1.0e200)))
  try huge.sample_gauss_jacobians(201) catch {
    _ => ()
  } noraise {
    _ => fail("unrepresentable measure")
  }
}
