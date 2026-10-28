///|
fn triangle() -> Mesh raise {
  let ns : Array[Node] = [
    { tag: 10, xyz: [0.0, 0.0, 0.0], dim: -1, entity: 0, parameters: [], },
    { tag: 33, xyz: [1.0, 0.0, 0.0], dim: -1, entity: 0, parameters: [], },
    { tag: 90, xyz: [0.0, 1.0, 0.0], dim: -1, entity: 0, parameters: [], },
  ]
  mesh(
    ns,
    [
      {
        tag: 77,
        kind: 2,
        nodes: [10, 33, 90],
        entity: 7,
        physical: [4],
        extra: [],
      },
    ],
    names=[{ dim: 2, tag: 4, name: "surface", }],
    fields=[
      {
        location: "NodeData",
        strings: ["temperature"],
        reals: [0.5],
        integers: [2, 1, 2, 0],
        entries: [{ tag: 10, values: [300.0], }, { tag: 90, values: [310.0], }],
      },
    ],
  )
}

///|
test "sparse tags preserve field association across text binary endian and size_t" {
  let m = triangle()
  for version in ["2.2", "4.1"] {
    for binary in [false, true] {
      for little in [false, true] {
        let widths = if version == "4.1" { [4, 8] } else { [8] }
        for size_width in widths {
          let n = decode(m.encode(version~, binary~, little~, size_width~))
          assert_eq(n.ns.map(n => n.tag), [10, 33, 90])
          assert_eq(n.es[0].nodes, [10, 33, 90])
          assert_eq(n.es[0].physical, [4])
          assert_eq(n.fs[0].entries[1].tag, 90)
          assert_eq(n.fs[0].integers, [2, 1, 2, 0])
        }
      }
    }
  }
}

///|
test "binary newline tag and explicit conversion loss" {
  let m = decode(triangle().encode(version="4.1", binary=true))
  let refused = try {
    ignore(m.encode(version="2.2"))
    false
  } catch {
    _ => true
  }
  assert_true(refused)
  let n = decode(m.encode(version="2.2", allow_loss=true, binary=true))
  assert_eq(n.ns[0].tag, 10)
  assert_eq(n.fs[0].reals, [0.5])
}

///|
test "owned snapshots and malformed references" {
  let m = triangle()
  let n = m.nodes()
  n[0].xyz[0] = 99.0
  assert_eq(m.ns[0].xyz[0], 0.0)
  let refused = try {
    ignore(mesh(n, [{ ..m.es[0], nodes: [1, 2, 3], }]))
    false
  } catch {
    _ => true
  }
  assert_true(refused)
}

///|
test "truncation and unknown text preservation" {
  let m = triangle()
  let text = m.encode()
  for i in [0, 1, 20, text.length() - 10] {
    assert_true(
      try {
        ignore(decode(Bytes::makei(i, j => text[j])))
        false
      } catch {
        _ => true
      },
    )
  }
  let u = mesh(m.ns, m.es, unknown=[{ name: "Comment", body: "opaque 77\n", }])
  assert_eq(decode(u.encode()).unknown[0].body, "opaque 77\n")
  assert_true(
    try {
      ignore(u.encode(binary=true))
      false
    } catch {
      _ => true
    },
  )
}
