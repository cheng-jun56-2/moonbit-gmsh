///|
test "field coverage catalog keeps exact section metadata without merging frames" {
  let base = integral_surface(9)
  let vector = integral_field(
    base,
    "NodeData",
    base.nodes().map(_ => [0.0, 0.0, 2.0]),
    step=3,
    time=[0.75],
  )
  let fields : Array[@gmsh.Field] = [
    {
      location: "NodeData",
      strings: ["温度"],
      reals: [],
      integers: [0, 1, 0],
      entries: [],
    },
    { ..vector, strings: ["velocity"], integers: [3, 3, 6], },
    { ..vector, strings: ["velocity", "custom"], integers: [3, 3, 6, 17, 99], },
    {
      location: "ElementData",
      strings: ["velocity", ""],
      reals: [0.75],
      integers: [3, 3, 1, 0],
      entries: [{ tag: 201, values: [0.0, 0.0, 2.0], }],
    },
  ]
  let source = integral_with(base, fields)
  let before = source.fields().to_json()
  let frames = source.field_frames()
  assert_eq(frames.map(f => f.field_index), [0, 1, 2, 3])
  assert_eq(frames.map(f => f.entries), [0, 6, 6, 1])
  assert_eq(frames.map(f => f.components), [1, 3, 3, 3])
  assert_eq(frames[0].name, "温度")
  assert_eq(frames[0].time, None)
  assert_eq(frames[1].time, Some(0.75))
  assert_eq(frames[1].time_step, 3)
  assert_eq(frames[1].partition, None)
  assert_eq(frames[2].partition, Some(17))
  assert_eq(frames[2].interpolation_scheme, Some("custom"))
  assert_eq(frames[3].interpolation_scheme, None)
  assert_eq(frames[3].partition, Some(0))
  assert_eq(frames[3].location, "ElementData")
  frames[0] = frames[1]
  assert_eq(source.field_frames()[0].field_index, 0)
  assert_eq(source.fields().to_json(), before)
}

///|
test "field coverage uses unique full nodes and faces across five surface families" {
  for kind in [2, 3, 9, 10, 16] {
    let base = integral_surface(kind)
    let n = base.nodes().length()
    let nodes = base.nodes()
    nodes.push({
      tag: 999,
      xyz: [2.0, 2.0, 2.0],
      dim: -1,
      entity: 0,
      parameters: [],
    })
    nodes.push({
      tag: 1000,
      xyz: [3.0, 3.0, 3.0],
      dim: -1,
      entity: 0,
      parameters: [],
    })
    let e = base.elements()[0]
    let entries = nodes
      .filter(v => v.tag != n)
      .map(v => @gmsh.Datum::{ tag: v.tag, values: [1.0, 2.0, 3.0], })
    let fields : Array[@gmsh.Field] = [
      {
        location: "NodeData",
        strings: ["sparse"],
        reals: [0.25],
        integers: [0, 3, n + 1],
        entries,
      },
      {
        location: "ElementData",
        strings: ["cell"],
        reals: [],
        integers: [0, 3, 2],
        entries: [
          { tag: 201, values: [0.0, 0.0, 2.0], },
          { tag: 900, values: [0.0, 0.0, 2.0], },
        ],
      },
    ]
    let source = @gmsh.mesh(
      nodes,
      [e, { ..e, tag: 701, }, { ..e, tag: 900, kind: 15, nodes: [999], }],
      fields~,
    )
    let r = source.surface_field_coverage(0)
    assert_eq(r.elements, 2)
    assert_eq(r.skipped_lower_dimension, 1)
    assert_eq(r.required_tags, n)
    assert_eq(r.present_tags, n - 1)
    assert_eq(r.missing_tags, [n])
    assert_eq(r.missing_count, 1)
    assert_true(!r.missing_truncated && !r.all_required_tags_present)
    let cell = source.surface_field_coverage(1)
    assert_eq(cell.field.entries, cell.required_tags)
    assert_eq(cell.required_tags, 2)
    assert_eq(cell.present_tags, 1)
    assert_eq(cell.missing_tags, [701])
  }
}

///|
test "field coverage caps only missing IDs and follows current requested and compact tags" {
  let base = integral_surface(2)
  let e = base.elements()[0]
  let empty : @gmsh.Field = {
    location: "NodeData",
    strings: ["empty"],
    reals: [],
    integers: [0, 3, 0],
    entries: [],
  }
  let source = @gmsh.mesh(
    base.nodes(),
    [e, { ..e, tag: 701, nodes: [3, 2, 1], }],
    fields=[empty, { ..empty, location: "ElementData", }],
  ).subset([701, 201])
  for
    (limit, expected, truncated) in [
      (0, [], true),
      (2, [3, 2], true),
      (3, [3, 2, 1], false),
    ] {
    let r = source.surface_field_coverage(0, max_missing=limit)
    assert_eq(r.missing_tags, expected)
    assert_eq(r.missing_count, 3)
    assert_eq(r.required_tags, 3)
    assert_eq(r.missing_truncated, truncated)
    assert_true(!r.all_required_tags_present)
  }
  assert_eq(source.surface_field_coverage(1).missing_tags, [701, 201])
  let binary = source.compact().encode(version="4.1", binary=true, little=false)
  let restored = @gmsh.decode(binary)
  assert_eq(restored.surface_field_coverage(1).missing_tags, [1, 2])
  let r = source.surface_field_coverage(0)
  r.missing_tags[0] = 999
  assert_eq(source.surface_field_coverage(0).missing_tags, [3, 2, 1])
}

///|
test "field coverage is not a geometry or integration certificate and rejects invalid queries" {
  let base = qmesh(2, [
    [0.0, 0.0, 0.0],
    [1.0e308, 0.0, 0.0],
    [0.0, 1.0e308, 0.0],
  ])
  let scalar = integral_field(base, "NodeData", base.nodes().map(_ => [1.0]))
  let source = integral_with(base, [
    scalar,
    { ..scalar, strings: ["scalar", "custom"], },
  ])
  for frame in [0, 1] {
    assert_true(source.surface_field_coverage(frame).all_required_tags_present)
    try source.integrate_surface_field(frame) catch {
      _ => ()
    } noraise {
      _ => fail("unsupported/range input unexpectedly integrated")
    }
  }
  for limit in [-1, 100001] {
    try source.surface_field_coverage(0, max_missing=limit) catch {
      _ => ()
    } noraise {
      _ => fail("invalid missing-ID cap accepted")
    }
  }
  for frame in [-1, 2] {
    try source.surface_field_coverage(frame) catch {
      _ => ()
    } noraise {
      _ => fail("invalid field index accepted")
    }
  }
  assert_true(integral_surface(2).field_frames().is_empty())
  let empty : @gmsh.Field = {
    location: "NodeData",
    strings: ["empty"],
    reals: [],
    integers: [0, 3, 0],
    entries: [],
  }
  for
    other in [
      @gmsh.mesh([], [], fields=[empty]),
      integral_with(dr_fixture(11, [1.0, 1.0, 1.0]), [empty]),
    ] {
    try other.surface_field_coverage(0) catch {
      _ => ()
    } noraise {
      _ => fail("non2D coverage accepted")
    }
  }
}
