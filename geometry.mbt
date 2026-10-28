///|
pub(all) struct Quality {
  tag : Int
  kind : Int
  measure : Double
  signed_volume : Double
  quality : Double
  degenerate : Bool
  inverted : Bool
} derive(ToJson)

///|
pub extend Quality with ToJson::{to_json}

///|
pub(all) struct Diagnostics {
  isolated : Array[Int]
  duplicate_nodes : Array[Array[Int]]
  repeated_connectivity : Array[Int]
  qualities : Array[Quality]
  unsupported_quality : Array[Int]
} derive(ToJson)

///|
pub extend Diagnostics with ToJson::{to_json}

///|
fn dot(a : Array[Double], b : Array[Double]) -> Double {
  a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
}

///|

///| Triangle quality = 4 sqrt(3) A / sum(edge^2); tetrahedron quality =

///| 12 (3 |V|)^(2/3) / sum(edge^2). Both are 1 for a regular simplex.

///| Scale edge-square sums, but keep products as mantissa/exponent pairs so

///| anisotropic meshes do not lose small axes to uniform-scale underflow.

///|
/// Degeneracy is scale-relative; triangle orientation in 3D is not "inverted".
pub fn Mesh::quality(
  self : Mesh,
  tag : Int,
  tolerance? : Double = 1.0e-12,
) -> Quality raise {
  if !finite(tolerance) || tolerance < 0.0 || tolerance >= 1.0 {
    bad("tolerance must be in [0,1)")
  }
  let e = match self.ei.get(tag) {
    Some(i) => self.es[i]
    None => {
      bad("unknown element tag")
      self.es[0]
    }
  }
  if e.kind != 2 && e.kind != 4 {
    bad("geometric quality supports linear triangles/tetrahedra only")
  }
  let pts = e.nodes.map(t => self.ns[self.ni[t]].xyz)
  let delta = pts.map(p => scaled_difference(p, pts[0]))
  let mut denominator = scaled(0.0)
  // Finite endpoint coordinates can have a nonrepresentable difference.
  // Keep each full edge and its square in the protected range, including
  // edges between non-origin corners; only final measure/quality need Double.
  for i in 0..<pts.length() {
    for j in 0..<i {
      for component in scaled_difference(pts[i], pts[j]) {
        denominator = denominator.plus(component.times(component))
      }
    }
  }
  if denominator.mantissa == 0.0 {
    return {
      tag,
      kind: e.kind,
      measure: 0.0,
      signed_volume: 0.0,
      quality: 0.0,
      degenerate: true,
      inverted: false,
    }
  }
  let normal = scaled_cross_values(delta[1], delta[2])
  let signed_measure = if e.kind == 2 {
    scaled_norm(normal).divide(scaled(2.0))
  } else {
    scaled_dot_values(normal, delta[3]).divide(scaled(6.0))
  }
  let measure = signed_measure.absolute().value("geometric measure")
  let q = if signed_measure.mantissa == 0.0 {
    0.0
  } else if e.kind == 2 {
    signed_measure
    .absolute()
    .times(scaled(4.0 * 3.0.sqrt()))
    .divide(denominator)
    .value("quality")
  } else {
    signed_measure
    .absolute()
    .times(scaled(3.0))
    .two_thirds()
    .times(scaled(12.0))
    .divide(denominator)
    .value("quality")
  }
  {
    tag,
    kind: e.kind,
    measure,
    signed_volume: if e.kind == 4 {
      if signed_measure.mantissa < 0.0 {
        -measure
      } else {
        measure
      }
    } else {
      0.0
    },
    quality: if q > 1.0 {
      1.0
    } else {
      q
    },
    degenerate: q <= tolerance,
    inverted: e.kind == 4 && signed_measure.mantissa < 0.0,
  }
}

///| Duplicate means exactly equal coordinates, including +0 == -0. No hidden

///|
/// epsilon merges; diagnostics do not mutate geometry or call it CAD-valid.
pub fn Mesh::diagnostics(
  self : Mesh,
  tolerance? : Double = 1.0e-12,
) -> Diagnostics raise {
  if !finite(tolerance) || tolerance < 0.0 || tolerance >= 1.0 {
    bad("invalid tolerance")
  }
  let used : Map[Int, Bool] = Map([])
  let repeated = []
  for e in self.es {
    let ids : Map[Int, Bool] = Map([])
    let mut duplicate = false
    for n in e.nodes {
      if ids.contains(n) {
        duplicate = true
      }
      ids[n] = true
      used[n] = true
    }
    if duplicate {
      repeated.push(e.tag)
    }
  }
  let grouped : Map[String, Array[Int]] = Map([])
  let order = []
  for n in self.ns {
    let key = n.xyz
      .map(x => if x == 0.0 { "0" } else { x.to_string() })
      .join(",")
    match grouped.get(key) {
      Some(a) => a.push(n.tag)
      None => {
        grouped[key] = [n.tag]
        order.push(key)
      }
    }
  }
  let duplicates = []
  for key in order {
    if grouped[key].length() > 1 {
      duplicates.push(grouped[key])
    }
  }
  let qualities = []
  let unsupported = []
  for e in self.es {
    if e.kind == 2 || e.kind == 4 {
      qualities.push(self.quality(e.tag, tolerance~))
    } else {
      unsupported.push(e.tag)
    }
  }
  {
    isolated: self.ns.filter(n => !used.contains(n.tag)).map(n => n.tag),
    duplicate_nodes: duplicates,
    repeated_connectivity: repeated,
    qualities,
    unsupported_quality: unsupported,
  }
}
