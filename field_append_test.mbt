///|
fn fa_recipient() -> @gmsh.Mesh raise {
  @gmsh.mesh(
    [
      {
        tag: 50,
        xyz: [0.0, 3.0, 0.0],
        dim: 2,
        entity: 7,
        parameters: [0.0, 3.0],
      },
      {
        tag: 90,
        xyz: [0.0, 0.0, 0.0],
        dim: 2,
        entity: 7,
        parameters: [0.0, 0.0],
      },
      {
        tag: 10,
        xyz: [2.0, 0.0, 0.0],
        dim: 2,
        entity: 7,
        parameters: [2.0, 0.0],
      },
      {
        tag: 2147483647,
        xyz: [9.0, 9.0, 9.0],
        dim: 1,
        entity: 3,
        parameters: [9.0],
      },
    ],
    [
      {
        tag: 201,
        kind: 2,
        nodes: [90, 10, 50],
        entity: 7,
        physical: [44],
        extra: [1, 17],
      },
      {
        tag: 8,
        kind: 1,
        nodes: [10, 50],
        entity: 3,
        physical: [9],
        extra: [1, 22],
      },
    ],
    entities=[
      {
        dim: 1,
        tag: 3,
        bounds: [0.0, 0.0, 0.0, 9.0, 9.0, 9.0],
        physical: [9],
        boundary: [],
      },
      {
        dim: 2,
        tag: 7,
        bounds: [0.0, 0.0, 0.0, 9.0, 9.0, 9.0],
        physical: [44],
        boundary: [3],
      },
    ],
    names=[
      { dim: 2, tag: 44, name: "wall", },
      { dim: 1, tag: 9, name: "edge", },
    ],
    fields=[
      {
        location: "NodeData",
        strings: ["温度", "", "recipient-extra"],
        reals: [0.5, 9.25],
        integers: [2, 1, 4, 17, 91],
        entries: [
          { tag: 50, values: [30.0], },
          { tag: 90, values: [10.0], },
          { tag: 10, values: [20.0], },
          { tag: 2147483647, values: [40.0], },
        ],
      },
    ],
    version="4.1",
  )
}

///|
fn fa_donor() -> @gmsh.Mesh raise {
  @gmsh.mesh(
    [
      {
        tag: 2147483647,
        xyz: [9.0, 9.0, 9.0],
        dim: -1,
        entity: 0,
        parameters: [],
      },
      { tag: 10, xyz: [2.0, 0.0, 0.0], dim: -1, entity: 0, parameters: [], },
      { tag: 50, xyz: [0.0, 3.0, 0.0], dim: -1, entity: 0, parameters: [], },
      { tag: 90, xyz: [0.0, 0.0, 0.0], dim: -1, entity: 0, parameters: [], },
    ],
    [
      { tag: 8, kind: 1, nodes: [10, 50], entity: 0, physical: [], extra: [], },
      {
        tag: 201,
        kind: 2,
        nodes: [90, 10, 50],
        entity: 0,
        physical: [],
        extra: [],
      },
    ],
    fields=[
      {
        location: "NodeData",
        strings: ["温度", "named-descriptor", "donor-extra"],
        reals: [0.5, 7.25],
        integers: [2, 1, 2, 31, 92],
        entries: [{ tag: 90, values: [100.0], }, { tag: 50, values: [300.0], }],
      },
      {
        location: "NodeData",
        strings: ["velocity"],
        reals: [],
        integers: [7, 3, 4],
        entries: [
          { tag: 2147483647, values: [9.0, 8.0, 7.0], },
          { tag: 10, values: [2.0, 3.0, 4.0], },
          { tag: 50, values: [5.0, 6.0, 7.0], },
          { tag: 90, values: [1.0, 2.0, 3.0], },
        ],
      },
      {
        location: "ElementData",
        strings: ["stress", "", "cell-extra"],
        reals: [0.0, 1.25],
        integers: [3, 9, 2, 0, 93],
        entries: [
          { tag: 8, values: [9.0, 8.0, 7.0, 6.0, 5.0, 4.0, 3.0, 2.0, 1.0], },
          { tag: 201, values: [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0], },
        ],
      },
      {
        location: "NodeData",
        strings: ["empty"],
        reals: [],
        integers: [8, 1, 0],
        entries: [],
      },
    ],
  )
}

///|
fn fa_with(
  m : @gmsh.Mesh,
  nodes? : Array[@gmsh.Node],
  elements? : Array[@gmsh.Element],
  fields? : Array[@gmsh.Field],
  unknown? : Array[@gmsh.Section],
) -> @gmsh.Mesh raise {
  @gmsh.mesh(
    nodes.unwrap_or(m.nodes()),
    elements.unwrap_or(m.elements()),
    entities=m.entities(),
    names=m.physical_names(),
    fields=fields.unwrap_or(m.fields()),
    unknown=unknown.unwrap_or(m.unknown_sections()),
    version=m.source_version(),
  )
}

///|
fn fa_snapshot(m : @gmsh.Mesh) -> Json {
  {
    "nodes": m.nodes().to_json(),
    "elements": m.elements().to_json(),
    "fields": m.fields().to_json(),
    "entities": m.entities().to_json(),
    "names": m.physical_names().to_json(),
    "unknown": m.unknown_sections().to_json(),
    "version": m.source_version().to_json(),
  }
}

///|
fn fa_reject(
  a : @gmsh.Mesh,
  b : @gmsh.Mesh,
  indices : Array[Int],
) -> Unit raise {
  let before_a = fa_snapshot(a)
  let before_b = fa_snapshot(b)
  let request = indices.copy()
  let rejected = try {
    let _ = a.append_fields(b, indices)
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
  assert_eq(fa_snapshot(a), before_a)
  assert_eq(fa_snapshot(b), before_b)
  assert_eq(indices, request)
}

///|
test "field append ordered raw sparse empty1/3/9 records preserve recipient context" {
  let target = fa_recipient()
  let donor = fa_donor()
  let before = fa_snapshot(target)
  let donor_before = fa_snapshot(donor)
  let received = target.append_fields(donor, [2, 0, 1, 3])
  assert_eq(received.nodes().to_json(), target.nodes().to_json())
  assert_eq(received.elements().to_json(), target.elements().to_json())
  assert_eq(received.entities().to_json(), target.entities().to_json())
  assert_eq(
    received.physical_names().to_json(),
    target.physical_names().to_json(),
  )
  assert_eq(received.source_version(), "4.1")
  let expected = [
    target.fields()[0],
    donor.fields()[2],
    donor.fields()[0],
    donor.fields()[1],
    donor.fields()[3],
  ]
  assert_eq(received.fields().to_json(), expected.to_json())
  assert_eq(received.field_frames().map(f => f.field_index), [0, 1, 2, 3, 4])
  assert_eq(received.field_frames().map(f => f.components), [1, 9, 1, 3, 1])
  assert_eq(received.field_frames().map(f => f.entries), [4, 2, 2, 4, 0])
  assert_eq(received.field_frames()[2].name, received.field_frames()[0].name)
  assert_eq(received.field_frames()[2].time, received.field_frames()[0].time)
  assert_eq(received.field_frames()[3].time, None)
  assert_eq(received.field_frames()[1].time, Some(0.0))
  assert_eq(fa_snapshot(target), before)
  assert_eq(fa_snapshot(donor), donor_before)
}

///|
test "field append rejects equal-count wrong domains coordinates kind and ordered roles" {
  let a = fa_recipient()
  let b = fa_donor()
  let nodes = b.nodes()
  nodes[0] = { ..nodes[0], tag: 999, }
  let fields = b
    .fields()
    .map(f => {
      ..f,
      entries: f.entries.map(d => {
        if d.tag == 2147483647 {
          { ..d, tag: 999, }
        } else {
          d
        }
      }),
    })
  fa_reject(a, fa_with(b, nodes~, fields~), [0])
  let nodes = b.nodes()
  nodes[1] = { ..nodes[1], xyz: [2.0000000000000004, 0.0, 0.0], }
  fa_reject(a, fa_with(b, nodes~), [0])
  let elements = b.elements()
  elements[1] = { ..elements[1], nodes: [10, 90, 50], }
  fa_reject(a, fa_with(b, elements~), [0])
  let elements = b.elements()
  elements[1] = { ..elements[1], tag: 202, }
  let fields = b
    .fields()
    .map(f => {
      if f.location == "ElementData" {
        {
          ..f,
          entries: f.entries.map(d => {
            if d.tag == 201 {
              { ..d, tag: 202, }
            } else {
              d
            }
          }),
        }
      } else {
        f
      }
    })
  fa_reject(a, fa_with(b, elements~, fields~), [0])
  let elements = b.elements()
  elements[1] = { ..elements[1], kind: 1, nodes: [90, 10], }
  fa_reject(a, fa_with(b, elements~), [0])
  let nodes = b.nodes()
  nodes.push({
    tag: 1234,
    xyz: [0.0, 0.0, 0.0],
    dim: -1,
    entity: 0,
    parameters: [],
  })
  fa_reject(a, fa_with(b, nodes~), [0])
}

///|
test "field append requires explicit opaque removal and exact unique donor indices" {
  let a = fa_recipient()
  let b = fa_donor()
  for indices in [[], [-1], [4], [0, 0]] {
    fa_reject(a, b, indices)
  }
  let opaque_a = fa_with(a, unknown=[{ name: "Opaque", body: "0\n", }])
  let opaque_b = fa_with(b, unknown=[{ name: "Opaque", body: "1\n", }])
  fa_reject(opaque_a, b, [0])
  fa_reject(a, opaque_b, [0])
  fa_reject(opaque_a, opaque_b, [0])
  assert_eq(
    opaque_a
    .without_unknown()
    .append_fields(opaque_b.without_unknown(), [0])
    .fields()
    .length(),
    2,
  )
}

///|
test "field append ownership isolates requests both sources and returned getters" {
  let a = fa_recipient()
  let b = fa_donor()
  let original_a = fa_snapshot(a)
  let original_b = fa_snapshot(b)
  let indices = [2, 0, 1, 3]
  let r = a.append_fields(b, indices)
  let before = fa_snapshot(r)
  indices[0] = 1
  let fields = r.fields()
  fields[1].strings[0] = "mutated"
  fields[1].reals[0] = 99.0
  fields[1].integers[0] = 99
  fields[1].entries[0].values[0] = 99.0
  let nodes = r.nodes()
  nodes[0].xyz[0] = 99.0
  nodes[0].parameters[0] = 99.0
  let elements = r.elements()
  elements[0].nodes[0] = 999
  elements[0].physical[0] = 99
  elements[0].extra[0] = 99
  assert_eq(fa_snapshot(r), before)
  assert_eq(fa_snapshot(a), original_a)
  assert_eq(fa_snapshot(b), original_b)
}

///|
test "field append preserves allowed repeated roles and signed-zero equality" {
  let a = fa_recipient()
  let b = fa_donor()
  let ae = a.elements()
  let be = b.elements()
  ae[0] = { ..ae[0], nodes: [90, 90, 50], }
  be[1] = { ..be[1], nodes: [90, 90, 50], }
  let nodes = b.nodes()
  nodes[3] = { ..nodes[3], xyz: [-0.0, 0.0, -0.0], }
  let r = fa_with(a, elements=ae).append_fields(
    fa_with(b, elements=be, nodes~),
    [0, 3],
  )
  assert_eq(r.elements()[0].nodes, [90, 90, 50])
  assert_eq(r.fields().length(), 3)
}

///|
test "field append keeps existing combined section budget with empty domains" {
  let f : @gmsh.Field = {
    location: "NodeData",
    strings: ["empty"],
    reals: [],
    integers: [0, 1, 0],
    entries: [],
  }
  let a = @gmsh.mesh([], [], fields=[ for _ in 0..<1023 => f ])
  let b = @gmsh.mesh([], [], fields=[f, f])
  assert_eq(a.append_fields(b, [1]).fields().length(), 1024)
  fa_reject(a, b, [0, 1])
}
