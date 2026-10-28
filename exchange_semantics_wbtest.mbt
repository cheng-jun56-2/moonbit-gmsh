///|
fn exchange_source(
  tags : Array[Int],
  point? : Bool = false,
  fields? : Array[Field] = [],
) -> Mesh raise {
  let nodes : Array[Node] = [
    { tag: 10, xyz: [0.0, 0.0, 0.0], dim: -1, entity: 0, parameters: [], },
    { tag: 20, xyz: [1.0, 0.0, 0.0], dim: -1, entity: 0, parameters: [], },
    { tag: 30, xyz: [0.0, 1.0, 0.0], dim: -1, entity: 0, parameters: [], },
  ]
  let elements = tags.mapi((i, entity) => Element::{
    tag: 77 + i,
    kind: if point {
      15
    } else {
      2
    },
    nodes: if point {
      [10]
    } else {
      [10, 20, 30]
    },
    entity,
    physical: [i + 4],
    extra: [],
  })
  mesh(nodes, elements, fields~, names=[
    { dim: if point { 0 } else { 2 }, tag: 4, name: "\uFEFFsurface", },
  ])
}

///|
test "exchange repair preserves maximal elementary IDs and allocates free gaps" {
  for
    (tags, expected, point) in [
      ([2147483647], [2147483647], false),
      ([2147483646, 0], [2147483646, 2147483647], false),
      ([2147483647, 1, 0], [2147483647, 1, 2], false),
      ([0, 1, 2147483647], [2, 1, 2147483647], false),
      ([2147483647], [2147483647], true),
    ] {
    let m = exchange_source(tags, point~)
    for
      (binary, little, size_width) in [
        (false, true, 8),
        (true, true, 8),
        (true, false, 8),
        (true, true, 4),
        (true, false, 4),
      ] {
      let n = decode(m.encode(version="4.1", binary~, little~, size_width~))
      assert_eq(n.elements().map(e => e.entity), expected)
      assert_eq(
        n.elements().map(e => e.physical),
        m.elements().map(e => e.physical),
      )
      let ids = n
        .entities()
        .filter(e => e.dim == (if point { 0 } else { 2 }))
        .map(e => e.tag)
      assert_eq(ids.length(), if point { 3 } else { expected.length() })
      assert_true(ids.all(t => t > 0))
      if point {
        let sorted = ids.copy()
        sorted.sort()
        assert_eq(sorted, [1, 2, 2147483647])
        assert_eq(n.nodes().map(n => n.entity), [2147483647, 1, 2])
      }
    }
  }
}

///|
test "exchange repair accepted UTF8 field strings roundtrip at code unit limit" {
  for
    text in [
      Array::make(4096, "x").join(""),
      Array::make(4096, "界").join(""),
      Array::make(2048, "😀").join(""),
      "\uFEFF" + Array::make(4095, "界").join(""),
    ] {
    assert_eq(text.length(), 4096)
    let f : Field = {
      location: "NodeData",
      strings: [text, "\uFEFFunits"],
      reals: [0.25, 1.0e-200],
      integers: [3, 1, 2, 0, 17],
      entries: [{ tag: 10, values: [300.0], }, { tag: 30, values: [310.0], }],
    }
    let m = exchange_source([7], fields=[f])
    for
      (version, binary, little, size_width) in [
        ("2.2", false, true, 8),
        ("2.2", true, false, 8),
        ("4.1", false, true, 8),
        ("4.1", true, true, 4),
      ] {
      let n = decode(m.encode(version~, binary~, little~, size_width~))
      assert_eq(n.fields().to_json(), m.fields().to_json())
      assert_eq(n.physical_names().to_json(), m.physical_names().to_json())
    }
  }
}

///|
fn exchange_quoted_raw(text : String) -> Bytes {
  @utf8.encode(
    "$MeshFormat\n2.2 0 8\n$EndMeshFormat\n$Nodes\n0\n$EndNodes\n$Elements\n0\n$EndElements\n$NodeData\n1\n\"" +
    text +
    "\"\n0\n3\n0\n1\n0\n$EndNodeData\n",
  )
}

///|
test "exchange repair rejects real overlimit malformed or unterminated quotes" {
  for
    text in [
      Array::make(4097, "x").join(""),
      Array::make(4097, "界").join(""),
      Array::make(2049, "😀").join(""),
    ] {
    try decode(exchange_quoted_raw(text)) catch {
      _ => ()
    } noraise {
      _ => fail("overlimit quoted field accepted")
    }
  }
  let raw = exchange_quoted_raw("unique")
  let needle = @utf8.encode("unique")
  let mut at = -1
  for i in 0..<(raw.length() - needle.length()) {
    if raw[i] == needle[0] && raw[i + 1] == needle[1] {
      at = i
      break
    }
  }
  assert_true(at > 0)
  let malformed = Bytes::makei(raw.length(), i => {
    if i == at {
      0xff
    } else {
      raw[i]
    }
  })
  try decode(malformed) catch {
    _ => ()
  } noraise {
    _ => fail("invalid UTF8 accepted")
  }
  let unterminated = Bytes::makei(at + 3, i => raw[i])
  try decode(unterminated) catch {
    _ => ()
  } noraise {
    _ => fail("unterminated quote accepted")
  }
}

///|
test "exchange ordered element runs preserve subset order across entities and types" {
  let base = exchange_source([7, 9, 7, 7, 7])
  let elements = base
    .elements()
    .mapi((i, e) => Element::{
      ..e,
      kind: if i == 3 {
        15
      } else {
        2
      },
      nodes: if i == 3 {
        [10]
      } else {
        e.nodes
      },
      physical: if e.entity == 7 {
        [44]
      } else {
        [55]
      },
    })
  let field : Field = {
    location: "ElementData",
    strings: ["velocity"],
    reals: [0.25],
    integers: [2, 3, 5],
    entries: elements.mapi((i, e) => Datum::{
      tag: e.tag,
      values: [0.0, 0.0, (i + 1).to_double()],
    }),
  }
  let source = mesh(base.nodes(), elements, fields=[field])
  for tags in [[77, 78, 79, 80, 81], [81, 78, 79, 80, 77]] {
    let selected = source.subset(tags)
    for
      (version, binary, little, size_width) in [
        ("2.2", false, true, 8),
        ("2.2", true, false, 8),
        ("4.1", false, true, 8),
        ("4.1", true, true, 8),
        ("4.1", true, false, 8),
        ("4.1", true, true, 4),
        ("4.1", true, false, 4),
      ] {
      let restored = decode(
        selected.encode(version~, binary~, little~, size_width~),
      )
      assert_eq(restored.elements().map(e => e.tag), tags)
      assert_eq(
        restored.elements().map(e => e.nodes),
        selected.elements().map(e => e.nodes),
      )
      assert_eq(
        restored.elements().map(e => e.physical),
        selected.elements().map(e => e.physical),
      )
      assert_eq(restored.fields().to_json(), selected.fields().to_json())
    }
  }
  let empty = source.subset([])
  assert_true(
    decode(empty.encode(version="4.1", binary=true)).elements().is_empty(),
  )
}
