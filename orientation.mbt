///|
/// Diagnostics at one face center, never a proof of global outwardness.
pub(all) struct FacetOrientation {
  element : Int
  owner : Int
  explicit_reversed : Bool
  center_normal : Array[Double]
  center_dot : Double
  status : String
} derive(ToJson)

///|
pub extend FacetOrientation with ToJson::{to_json}

///|
pub fn Boundary::orientation_report(self : Boundary) -> Array[FacetOrientation] {
  self.orientation_details.map(o => {
    ..o,
    center_normal: o.center_normal.copy(),
  })
}

///|
fn facet_reversed(nodes : Array[Int], expected : Array[Int], dim : Int) -> Bool {
  let c = facet_corners(nodes.length(), dim)
  if c == 2 {
    return nodes[0] != expected[0]
  }
  if c >= 3 {
    for offset in 0..<c {
      if nodes[0] == expected[offset] &&
        nodes[1] == expected[(offset + c - 1) % c] {
        return true
      }
    }
  }
  false
}

///|
fn Mesh::facet_orientation(
  self : Mesh,
  face : Element,
  owner : Element,
  expected : Array[Int],
  dim : Int,
) -> FacetOrientation raise {
  let reverse = facet_reversed(face.nodes, expected, dim - 1)
  let mut normal : Array[Double] = []
  let mut center_dot = 0.0
  let mut status = "not_volume_face"
  if dim == 3 {
    let pts = face.nodes.map(n => self.ns[self.ni[n]].xyz)
    let offsets = pts.map(p => scaled_difference(p, pts[0]))
    let c = facet_corners(face.nodes.length(), 2)
    let b = if face.kind == 9 || face.kind == 10 || face.kind == 16 {
      basis(
        face.kind,
        if face.kind == 9 {
          [1.0 / 3.0, 1.0 / 3.0]
        } else {
          [0.0, 0.0]
        },
      )
    } else if c == 3 {
      [
        Jet::{ v: 1.0 / 3.0, d: [-1.0, -1.0, 0.0], },
        Jet::{ v: 1.0 / 3.0, d: [1.0, 0.0, 0.0], },
        Jet::{ v: 1.0 / 3.0, d: [0.0, 1.0, 0.0], },
      ]
    } else {
      [
        Jet::{ v: 0.25, d: [-0.25, -0.25, 0.0], },
        Jet::{ v: 0.25, d: [0.25, -0.25, 0.0], },
        Jet::{ v: 0.25, d: [0.25, 0.25, 0.0], },
        Jet::{ v: 0.25, d: [-0.25, 0.25, 0.0], },
      ]
    }
    let center = [scaled(0.0), scaled(0.0), scaled(0.0)]
    let columns = [
      [scaled(0.0), scaled(0.0), scaled(0.0)],
      [scaled(0.0), scaled(0.0), scaled(0.0)],
    ]
    for i, p in offsets {
      for k in 0..<3 {
        center[k] = center[k].plus(p[k].times(scaled(b[i].v)))
        for j in 0..<2 {
          columns[j][k] = columns[j][k].plus(p[k].times(scaled(b[i].d[j])))
        }
      }
    }
    let cross = scaled_cross_values(columns[0], columns[1])
    normal = scaled_unit(cross)
    let primary = if owner.kind == 4 || owner.kind == 11 {
      4
    } else if owner.kind == 5 || owner.kind == 12 || owner.kind == 17 {
      8
    } else if owner.kind == 6 {
      6
    } else {
      5
    }
    let parent = [scaled(0.0), scaled(0.0), scaled(0.0)]
    for t in owner.nodes[:primary] {
      let offset = scaled_difference(self.ns[self.ni[t]].xyz, pts[0])
      for k in 0..<3 {
        parent[k] = parent[k].plus(
          offset[k].divide(scaled(primary.to_double())),
        )
      }
    }
    let delta = [ for k in 0..<3 => center[k].plus(parent[k].negative()) ]
    center_dot = scaled_dot(delta, normal).value("face center orientation")
    status = if cross.all(x => x.mantissa == 0.0) || center_dot == 0.0 {
      "indeterminate_at_center"
    } else if center_dot > 0.0 {
      "outward_at_center"
    } else {
      "inward_at_center"
    }
  }
  {
    element: face.tag,
    owner: owner.tag,
    explicit_reversed: reverse,
    center_normal: normal,
    center_dot,
    status,
  }
}
