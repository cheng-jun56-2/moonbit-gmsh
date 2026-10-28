///|
/// Supplementary corner-only metrics. The edge ratio is longest/shortest
/// straight topological corner edge (ideal cube1, reference right tetra sqrt2).
/// Dihedral is defined here only for the tetrahedral corner polyhedron;
/// neither metric evaluates curvature or certifies the curved element.
fn Mesh::corner_metrics(self : Mesh, e : Element) -> (Double?, Double?) raise {
  let dim = element_shape(e.kind).0
  let c = match e.kind {
    8 => 2
    9 => 3
    10 | 16 => 4
    11 => 4
    _ => 8
  }
  let raw = e.nodes[:c].map(t => self.ns[self.ni[t]].xyz)
  let edges = if e.kind == 11 {
    [[0, 1], [1, 2], [2, 0], [0, 3], [2, 3], [1, 3]]
  } else if dim == 3 {
    [
      [0, 1],
      [1, 2],
      [2, 3],
      [3, 0],
      [4, 5],
      [5, 6],
      [6, 7],
      [7, 4],
      [0, 4],
      [1, 5],
      [2, 6],
      [3, 7],
    ]
  } else if dim == 1 {
    [[0, 1]]
  } else if c == 3 {
    [[0, 1], [1, 2], [2, 0]]
  } else {
    [[0, 1], [1, 2], [2, 3], [3, 0]]
  }
  let mut lo : Scaled? = None
  let mut hi = scaled(0.0)
  for edge in edges {
    let length = scaled_norm(scaled_difference(raw[edge[0]], raw[edge[1]]))
    lo = Some(
      match lo {
        None => length
        Some(old) =>
          if scaled_positive_less(length, old) {
            length
          } else {
            old
          }
      },
    )
    if scaled_positive_less(hi, length) {
      hi = length
    }
  }
  let ratio = match lo {
    Some(low) if low.mantissa != 0.0 =>
      Some(hi.divide(low).value("corner edge ratio")) catch {
        _ => None
      }
    _ => None
  }
  let mut angle : Double? = None
  if e.kind == 11 {
    let normals : Array[Array[Double]] = []
    for f in [[0, 2, 1], [0, 1, 3], [1, 2, 3], [2, 0, 3]] {
      let cross = scaled_triangle_cross(f.map(i => raw[i]))
      if cross.all(x => x.mantissa == 0.0) {
        return (ratio, None)
      }
      normals.push(scaled_unit(cross))
    }
    let mut minimum = 180.0
    for i in 0..<4 {
      for j in 0..<i {
        let cosine = dot(normals[i], normals[j]).max(-1.0).min(1.0)
        let sine = scaled_norm(scaled_cross(normals[i], normals[j])).value(
          "corner dihedral sine",
        ) catch {
          _ => return (ratio, None)
        }
        // atan2 avoids losing a small positive angle in PI-acos(-1+epsilon).
        minimum = minimum.min(@math.atan2(sine, -cosine) * 180.0 / @math.PI)
      }
    }
    angle = Some(minimum)
  }
  (ratio, angle)
}
