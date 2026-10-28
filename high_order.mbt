///|
/// Quadratic reference-node coordinates in raw Gmsh order. Checked against
/// Gmsh4.15.2 getElementProperties. No VTK permutation inside the MSH model.
fn reference_nodes(kind : Int) -> Array[Array[Double]] raise {
  match kind {
    8 => [[-1.0], [1.0], [0.0]]
    9 =>
      [[0.0, 0.0], [1.0, 0.0], [0.0, 1.0], [0.5, 0.0], [0.5, 0.5], [0.0, 0.5]]
    10 =>
      [
        [-1.0, -1.0],
        [1.0, -1.0],
        [1.0, 1.0],
        [-1.0, 1.0],
        [0.0, -1.0],
        [1.0, 0.0],
        [0.0, 1.0],
        [-1.0, 0.0],
        [0.0, 0.0],
      ]
    11 =>
      [
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
      ]
    12 =>
      [
        [-1.0, -1.0, -1.0],
        [1.0, -1.0, -1.0],
        [1.0, 1.0, -1.0],
        [-1.0, 1.0, -1.0],
        [-1.0, -1.0, 1.0],
        [1.0, -1.0, 1.0],
        [1.0, 1.0, 1.0],
        [-1.0, 1.0, 1.0],
        [0.0, -1.0, -1.0],
        [-1.0, 0.0, -1.0],
        [-1.0, -1.0, 0.0],
        [1.0, 0.0, -1.0],
        [1.0, -1.0, 0.0],
        [0.0, 1.0, -1.0],
        [1.0, 1.0, 0.0],
        [-1.0, 1.0, 0.0],
        [0.0, -1.0, 1.0],
        [-1.0, 0.0, 1.0],
        [1.0, 0.0, 1.0],
        [0.0, 1.0, 1.0],
        [0.0, 0.0, -1.0],
        [0.0, -1.0, 0.0],
        [-1.0, 0.0, 0.0],
        [1.0, 0.0, 0.0],
        [0.0, 1.0, 0.0],
        [0.0, 0.0, 1.0],
        [0.0, 0.0, 0.0],
      ]
    16 =>
      [
        [-1.0, -1.0],
        [1.0, -1.0],
        [1.0, 1.0],
        [-1.0, 1.0],
        [0.0, -1.0],
        [1.0, 0.0],
        [0.0, 1.0],
        [-1.0, 0.0],
      ]
    17 =>
      [
        [-1.0, -1.0, -1.0],
        [1.0, -1.0, -1.0],
        [1.0, 1.0, -1.0],
        [-1.0, 1.0, -1.0],
        [-1.0, -1.0, 1.0],
        [1.0, -1.0, 1.0],
        [1.0, 1.0, 1.0],
        [-1.0, 1.0, 1.0],
        [0.0, -1.0, -1.0],
        [-1.0, 0.0, -1.0],
        [-1.0, -1.0, 0.0],
        [1.0, 0.0, -1.0],
        [1.0, -1.0, 0.0],
        [0.0, 1.0, -1.0],
        [1.0, 1.0, 0.0],
        [-1.0, 1.0, 0.0],
        [0.0, -1.0, 1.0],
        [-1.0, 0.0, 1.0],
        [1.0, 0.0, 1.0],
        [0.0, 1.0, 1.0],
      ]
    _ => {
      bad("quadratic basis supports Line3/Tri6/Quad8/Quad9/Tet10/Hex20/Hex27")
      []
    }
  }
}

///|
fn quadratic_facets(kind : Int) -> Array[Array[Int]] raise {
  match kind {
    8 => [[0], [1]]
    9 => [[0, 1, 3], [1, 2, 4], [2, 0, 5]]
    10 => [[0, 1, 4], [1, 2, 5], [2, 3, 6], [3, 0, 7]]
    16 => [[0, 1, 4], [1, 2, 5], [2, 3, 6], [3, 0, 7]]
    11 =>
      [
        [0, 2, 1, 6, 5, 4],
        [0, 1, 3, 4, 9, 7],
        [1, 2, 3, 5, 8, 9],
        [2, 0, 3, 6, 7, 8],
      ]
    12 =>
      [
        [0, 3, 2, 1, 9, 13, 11, 8, 20],
        [4, 5, 6, 7, 16, 18, 19, 17, 25],
        [0, 1, 5, 4, 8, 12, 16, 10, 21],
        [1, 2, 6, 5, 11, 14, 18, 12, 23],
        [2, 3, 7, 6, 13, 15, 19, 14, 24],
        [3, 0, 4, 7, 9, 10, 17, 15, 22],
      ]
    17 =>
      [
        [0, 3, 2, 1, 9, 13, 11, 8],
        [4, 5, 6, 7, 16, 18, 19, 17],
        [0, 1, 5, 4, 8, 12, 16, 10],
        [1, 2, 6, 5, 11, 14, 18, 12],
        [2, 3, 7, 6, 13, 15, 19, 14],
        [3, 0, 4, 7, 9, 10, 17, 15],
      ]
    _ => {
      bad("unsupported high-order facet topology")
      []
    }
  }
}

///|
/// A facet retains corners first, then one node per consecutive edge and
/// optional center. Compare the geometric role of each node, never rotate the
/// entire high-order row as though all entries were polygon vertices.
fn facet_corners(n : Int, dim : Int) -> Int {
  if dim == 0 {
    1
  } else if dim == 1 {
    2
  } else if n == 3 || n == 6 {
    3
  } else {
    4
  }
}

///|
fn facet_identity(nodes : Array[Int], dim : Int) -> String {
  facet_key(nodes[:facet_corners(nodes.length(), dim)].to_owned())
}

///|
fn compatible_facet(a : Array[Int], b : Array[Int], dim : Int) -> Bool {
  if a.length() != b.length() {
    return false
  }
  let c = facet_corners(a.length(), dim)
  if a.length() == c {
    return same_cycle(a, b)
  }
  if c == 2 {
    return same_cycle(a[:2].to_owned(), b[:2].to_owned()) && a[2] == b[2]
  }
  for offset in 0..<c {
    for reverse in [false, true] {
      let mut ok = true
      for i in 0..<c {
        let j = if reverse { (offset + c - i) % c } else { (offset + i) % c }
        let edge = if reverse { (j + c - 1) % c } else { j }
        ok = ok && a[i] == b[j] && a[c + i] == b[c + edge]
      }
      if a.length() == 2 * c + 1 {
        ok = ok && a[2 * c] == b[2 * c]
      }
      if ok {
        return true
      }
    }
  }
  false
}

///|
fn facet_kind(nodes : Array[Int], dim : Int) -> Int {
  if dim == 0 {
    15
  } else if dim == 1 {
    if nodes.length() == 3 {
      8
    } else {
      1
    }
  } else {
    match nodes.length() {
      3 => 2
      4 => 3
      6 => 9
      8 => 16
      _ => 10
    }
  }
}

///|
/// First derivatives of polynomial shape functions through forward-mode
/// algebra. This is internal geometry, not a numerical finite-difference oracle.
priv struct Jet {
  v : Double
  d : Array[Double]
}

///|
fn jconst(v : Double) -> Jet {
  { v, d: [0.0, 0.0, 0.0], }
}

///|
fn jadd(a : Jet, b : Jet) -> Jet {
  { v: a.v + b.v, d: [ for i in 0..<3 => a.d[i] + b.d[i] ], }
}

///|
fn jscale(a : Jet, s : Double) -> Jet {
  { v: a.v * s, d: a.d.map(x => x * s), }
}

///|
fn jmul(a : Jet, b : Jet) -> Jet {
  { v: a.v * b.v, d: [ for i in 0..<3 => a.d[i] * b.v + a.v * b.d[i] ], }
}

///|
fn jlag(x : Jet, node : Double) -> Jet {
  if node == 0.0 {
    jadd(jconst(1.0), jscale(jmul(x, x), -1.0))
  } else {
    jscale(jmul(x, jadd(x, jconst(node))), 0.5)
  }
}

///|
fn basis(kind : Int, p : Array[Double]) -> Array[Jet] raise {
  let dim = element_shape(kind).0
  if p.length() != dim || p.any(x => !finite(x)) {
    bad("invalid reference coordinates")
  }
  let x = [
    for i in 0..<3 => {
      Jet::{
        v: if i < dim {
          p[i]
        } else {
          0.0
        },
        d: [
          for j in 0..<3 => if i == j { 1.0 } else { 0.0 }
        ],
      }
    }
  ]
  if kind == 8 {
    return [-1.0, 1.0, 0.0].map(t => jlag(x[0], t))
  }
  if kind == 9 || kind == 11 {
    let mut l0 = jconst(1.0)
    for i in 0..<dim {
      l0 = jadd(l0, jscale(x[i], -1.0))
    }
    let l = [l0, x[0], x[1]]
    if dim == 3 {
      l.push(x[2])
    }
    let out = l.map(a => jmul(a, jadd(jscale(a, 2.0), jconst(-1.0))))
    let edges = if dim == 2 {
      [[0, 1], [1, 2], [2, 0]]
    } else {
      [[0, 1], [1, 2], [2, 0], [0, 3], [2, 3], [1, 3]]
    }
    for e in edges {
      out.push(jscale(jmul(l[e[0]], l[e[1]]), 4.0))
    }
    return out
  }
  let refs = reference_nodes(kind)
  if kind == 10 || kind == 12 {
    return refs.map(n => {
      let mut a = jconst(1.0)
      for i in 0..<dim {
        a = jmul(a, jlag(x[i], n[i]))
      }
      a
    })
  }
  // Serendipity Quad8/Hex20: corners use a multilinear product times
  // (sum(sign_i*x_i) - (dim-1)); edge nodes use (1-x_axis^2).
  refs.map(n => {
    let mut a = jconst(1.0)
    let mut sum = jconst(-(dim - 1).to_double())
    let mut corner = true
    for i in 0..<dim {
      if n[i] == 0.0 {
        corner = false
        a = jmul(a, jadd(jconst(1.0), jscale(jmul(x[i], x[i]), -1.0)))
      } else {
        a = jmul(a, jadd(jconst(1.0), jscale(x[i], n[i])))
        sum = jadd(sum, jscale(x[i], n[i]))
      }
    }
    if corner {
      jscale(jmul(a, sum), if dim == 3 { 0.125 } else { 0.25 })
    } else {
      jscale(a, if dim == 3 { 0.25 } else { 0.5 })
    }
  })
}

///|
fn gauss2(kind : Int) -> Array[Array[Double]] raise {
  let q = 1.0 / 3.0.sqrt()
  match kind {
    8 => [[-q], [q]]
    9 =>
      [[1.0 / 6.0, 1.0 / 6.0], [2.0 / 3.0, 1.0 / 6.0], [1.0 / 6.0, 2.0 / 3.0]]
    11 => {
      let a = (5.0 + 3.0 * 5.0.sqrt()) / 20.0
      let b = (5.0 - 5.0.sqrt()) / 20.0
      [[b, b, b], [a, b, b], [b, a, b], [b, b, a]]
    }
    10 | 16 => [[-q, -q], [-q, q], [q, -q], [q, q]]
    12 | 17 =>
      [
        [-q, -q, -q],
        [-q, -q, q],
        [-q, q, -q],
        [-q, q, q],
        [q, -q, -q],
        [q, -q, q],
        [q, q, -q],
        [q, q, q],
      ]
    _ => {
      bad("Gauss2 sampling supports quadratic families only")
      []
    }
  }
}

///|
/// Hierarchical evaluation: a linear/trilinear corner map plus quadratic
/// nodal remainders. Directly summing large Lagrange derivative terms creates
/// spurious cross-axis derivatives on a very anisotropic affine cell.
priv struct RangeJet {
  v : Scaled
  d : Array[Scaled]
}

///|
fn range_constant(v : Scaled) -> RangeJet {
  { v, d: [scaled(0.0), scaled(0.0), scaled(0.0)], }
}

///|
fn range_weighted(b : Jet, value : Scaled) -> RangeJet {
  { v: value.times(scaled(b.v)), d: b.d.map(x => value.times(scaled(x))), }
}

///|
fn range_add(a : RangeJet, b : RangeJet) -> RangeJet {
  { v: a.v.plus(b.v), d: [ for i in 0..<3 => a.d[i].plus(b.d[i]) ], }
}

///|
/// The relative difference between two finite nodes may exceed Double even
/// when interpolation and every returned derivative remain representable.
fn range_lerp(a : RangeJet, b : RangeJet, t : Jet) -> RangeJet {
  let delta = b.v.plus(a.v.negative())
  {
    v: a.v.plus(delta.times(scaled(t.v))),
    d: [
      for i in 0..<3 => {
        a.d[i]
        .plus(b.d[i].plus(a.d[i].negative()).times(scaled(t.v)))
        .plus(delta.times(scaled(t.d[i])))
      }
    ],
  }
}

///|
fn primary_count(kind : Int) -> Int {
  match kind {
    8 => 2
    9 => 3
    11 => 4
    10 | 16 => 4
    _ => 8
  }
}

///|
/// Coordinates relative to the first corner, evaluated with differences and
/// nested linear interpolation so independent affine axes cancel exactly.
fn Mesh::corner_map(
  self : Mesh,
  e : Element,
  p : Array[Double],
) -> Array[RangeJet] {
  let origin = self.ns[self.ni[e.nodes[0]]].xyz
  let coords = e.nodes[:primary_count(e.kind)].map(t => {
    scaled_difference(self.ns[self.ni[t]].xyz, origin)
  })
  let x = p.mapi((i, v) => Jet::{
    v,
    d: [
      for j in 0..<3 => if i == j { 1.0 } else { 0.0 }
    ],
  })
  if e.kind == 9 || e.kind == 11 {
    return [
      for k in 0..<3 => {
        let mut a = range_constant(scaled(0.0))
        for i in 0..<p.length() {
          a = range_add(a, range_weighted(x[i], coords[i + 1][k]))
        }
        a
      }
    ]
  }
  let t = x.map(v => jscale(jadd(v, jconst(1.0)), 0.5))
  [
    for k in 0..<3 => {
      let lo = range_lerp(
        range_constant(coords[0][k]),
        range_constant(coords[1][k]),
        t[0],
      )
      if e.kind == 8 {
        lo
      } else {
        let hi = range_lerp(
          range_constant(coords[3][k]),
          range_constant(coords[2][k]),
          t[0],
        )
        let bottom = range_lerp(lo, hi, t[1])
        if e.kind == 10 || e.kind == 16 {
          bottom
        } else {
          let tl = range_lerp(
            range_constant(coords[4][k]),
            range_constant(coords[5][k]),
            t[0],
          )
          let th = range_lerp(
            range_constant(coords[7][k]),
            range_constant(coords[6][k]),
            t[0],
          )
          range_lerp(bottom, range_lerp(tl, th, t[1]), t[2])
        }
      }
    }
  ]
}

///|
/// P1/Q1 lies in each supported quadratic space. Interpolate only the
/// deviations of higher-order nodes from that corner map, without tolerances
/// that might erase a real, very small curvature.
fn Mesh::quadratic_remainders(
  self : Mesh,
  e : Element,
) -> Array[Array[Scaled]] raise {
  let origin = self.ns[self.ni[e.nodes[0]]].xyz
  let refs = reference_nodes(e.kind)
  refs.mapi((i, p) => {
    if i < primary_count(e.kind) {
      [scaled(0.0), scaled(0.0), scaled(0.0)]
    } else {
      let corner = self.corner_map(e, p)
      let actual = self.ns[self.ni[e.nodes[i]]].xyz
      // Form the absolute corner prediction before subtracting the actual
      // node. (actual-origin)-offset erases a tiny real midpoint displacement
      // when origin and offset are large and opposite.
      [
        for k in 0..<3 => {
          scaled(actual[k]).plus(scaled(origin[k]).plus(corner[k].v).negative())
        }
      ]
    }
  })
}

///|
fn Mesh::map_quadratic(
  self : Mesh,
  e : Element,
  p : Array[Double],
) -> (Array[Double], Array[Array[Double]]) raise {
  let b = basis(e.kind, p)
  let coordinates = self.corner_map(e, p)
  let origin = self.ns[self.ni[e.nodes[0]]].xyz
  for k in 0..<3 {
    coordinates[k] = {
      ..coordinates[k],
      v: scaled(origin[k]).plus(coordinates[k].v),
    }
  }
  let remainders = self.quadratic_remainders(e)
  for i in primary_count(e.kind)..<e.nodes.length() {
    for k in 0..<3 {
      coordinates[k] = range_add(
        coordinates[k],
        range_weighted(b[i], remainders[i][k]),
      )
    }
  }
  let xyz = [ for k in 0..<3 => coordinates[k].v.value("quadratic coordinate") ]
  let jac = [
    for j in 0..<3 => {
      [
        for k in 0..<3 => coordinates[k].d[j].value("quadratic derivative")
      ]
    }
  ]
  if xyz.any(x => !finite(x)) || jac.any(v => v.any(x => !finite(x))) {
    bad("quadratic coordinate/derivative overflow")
  }
  (xyz, jac)
}

///|
pub(all) struct JacobianSample {
  reference : Array[Double]
  xyz : Array[Double]
  columns : Array[Array[Double]]
  measure : Double
  signed_jacobian : Double?
  scaled_jacobian : Double
  normal : Array[Double]
} derive(ToJson)

///|
pub extend JacobianSample with ToJson::{to_json}

///|
pub(all) struct SamplingQualityReport {
  tag : Int
  kind : Int
  dimension : Int
  rule : String
  samples : Array[JacobianSample]
  minimum_measure : Double
  minimum_signed : Double?
  nonpositive_samples : Int
  globally_certified : Bool
  corner_edge_ratio : Double?
  corner_minimum_dihedral_degrees : Double?
} derive(ToJson)

///|
pub extend SamplingQualityReport with ToJson::{to_json}

///|
/// Level1 only: Gauss2 values are NOT an everywhere-positive certificate.
/// For embedded surfaces measure=|du x dv|. An optional reference_normal gives
/// a signed projection, not a global orientation/injectivity guarantee.
/// Scaled Jacobian is det/(column norm product), without ideal-simplex scaling.
pub fn Mesh::sample_gauss_jacobians(
  self : Mesh,
  tag : Int,
  reference_normal? : Array[Double] = [],
) -> SamplingQualityReport raise {
  let e = match self.ei.get(tag) {
    Some(i) => self.es[i]
    None => {
      bad("unknown sampling element tag")
      self.es[0]
    }
  }
  let dim = element_shape(e.kind).0
  let points = gauss2(e.kind)
  if !reference_normal.is_empty() &&
    (
      dim != 2 ||
      reference_normal.length() != 3 ||
      reference_normal.any(x => !finite(x)) ||
      reference_normal.all(x => x == 0.0)
    ) {
    bad("reference normal requires a finite nonzero 3D vector on a surface")
  }
  let samples : Array[JacobianSample] = []
  let mut minimum = 1.7976931348623157e308
  let mut signed_min : Double? = None
  let mut nonpositive = 0
  for p in points {
    let (xyz, j) = self.map_quadratic(e, p)
    let area_vector = if dim >= 2 { scaled_cross(j[0], j[1]) } else { [] }
    let signed_measure = if dim == 3 {
      scaled_dot(area_vector, j[2])
    } else if dim == 2 {
      scaled_norm(area_vector)
    } else {
      scaled_norm(j[0].map(scaled))
    }
    let measure = signed_measure.absolute().value("Jacobian measure")
    let signed = if dim == 3 {
      Some(signed_measure.value("signed Jacobian"))
    } else if !reference_normal.is_empty() {
      Some(
        scaled_dot(area_vector, reference_normal)
        .divide(scaled_norm(reference_normal.map(scaled)))
        .value("signed surface projection"),
      )
    } else {
      None
    }
    let mut denominator = scaled(1.0)
    for i in 0..<dim {
      denominator = denominator.times(scaled_norm(j[i].map(scaled)))
    }
    let scaled_j = if denominator.mantissa == 0.0 {
      0.0
    } else {
      signed_measure.divide(denominator).value("scaled Jacobian")
    }
    minimum = minimum.min(measure)
    if signed is Some(v) {
      signed_min = Some(
        match signed_min {
          Some(old) => old.min(v)
          None => v
        },
      )
    }
    if signed.unwrap_or(measure) <= 0.0 {
      nonpositive = nonpositive + 1
    }
    samples.push({
      reference: p,
      xyz,
      columns: j,
      measure,
      signed_jacobian: signed,
      scaled_jacobian: scaled_j,
      normal: if area_vector.is_empty() {
        []
      } else {
        scaled_unit(area_vector)
      },
    })
  }
  let (edge_ratio, dihedral) = self.corner_metrics(e)
  {
    tag,
    kind: e.kind,
    dimension: dim,
    corner_edge_ratio: edge_ratio,
    corner_minimum_dihedral_degrees: dihedral,
    rule: if e.kind == 10 || e.kind == 16 {
      "CompositeGauss2"
    } else {
      "Gauss2"
    },
    samples,
    minimum_measure: minimum,
    minimum_signed: signed_min,
    nonpositive_samples: nonpositive,
    globally_certified: false,
  }
}
