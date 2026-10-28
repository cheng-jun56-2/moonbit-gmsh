///|
test "nonmanifold incidence is reported without quadratic expansion" {
  let m = triangle()
  let es = [m.es[0], { ..m.es[0], tag: 78, }, { ..m.es[0], tag: 79, }]
  let t = mesh(m.ns, es).topology()
  assert_eq(t.nonmanifold.length(), 3)
  assert_eq(t.nonmanifold[0].owners, [77, 78, 79])
  assert_true(t.boundary.is_empty())
}

///|
test "small nonzero area is not squared into zero" {
  let ns = triangle().nodes()
  ns[2] = { ..ns[2], xyz: [0.0, 1.0e-200, 0.0], }
  let m = mesh(ns, triangle().es)
  assert_true(m.quality(77).measure > 0.0)
  assert_true(m.quality(77).degenerate)
}

///|
test "incomplete entity classification and inconsistent legacy groups rejected" {
  let m = triangle()
  let entity : Entity = {
    dim: 2,
    tag: 7,
    bounds: [0.0, 0.0, 0.0, 1.0, 1.0, 0.0],
    physical: [4],
    boundary: [],
  }
  assert_true(
    try {
      ignore(mesh(m.ns, m.es, entities=[entity]))
      false
    } catch {
      _ => true
    },
  )
  let inconsistent = mesh(m.ns, [
    m.es[0],
    { ..m.es[0], tag: 78, physical: [5], },
  ])
  assert_true(
    try {
      ignore(inconsistent.encode(version="4.1"))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "CRLF parsing and repeated core section rejection" {
  let raw = triangle().encode()
  let text = @utf8.decode(raw)
  let crlf = text.replace_all(old="\n", new="\r\n")
  assert_eq(decode(@utf8.encode(crlf)).ns.length(), 3)
  assert_true(
    try {
      ignore(decode(@utf8.encode(text + "$Nodes\n0\n$EndNodes\n")))
      false
    } catch {
      _ => true
    },
  )
}
