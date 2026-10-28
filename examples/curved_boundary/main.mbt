///|
/// A self-authored curved Tet10, not a customer mesh or validity certificate.
fn main raise {
  let points = [
    [0.0, 0.0, 0.0],
    [1.0, 0.0, 0.0],
    [0.0, 1.0, 0.0],
    [0.0, 0.0, 1.0],
    [0.5, 0.0, -0.05],
    [0.5, 0.5, -0.05],
    [0.0, 0.5, -0.05],
    [-0.05, 0.0, 0.5],
    [0.0, 0.5, 0.5],
    [0.5, 0.0, 0.5],
  ]
  let m = @gmsh.mesh(
    points.mapi((i, xyz) => {
      tag: 10 + i * 7,
      xyz,
      dim: -1,
      entity: 0,
      parameters: [],
    }),
    [
      {
        tag: 201,
        kind: 11,
        nodes: [
          for i in 0..<10 => 10 + i * 7
        ],
        entity: 0,
        physical: [],
        extra: [],
      },
    ],
  )
  let boundary = m.extract_boundary()
  println(boundary.report().to_json().stringify())
  println(boundary.orientation_report().to_json().stringify())
  println(m.sample_gauss_jacobians(201).to_json().stringify())
  let (_, loss) = m.export_to_obj(@gmsh.PermissiveWithAudit)
  println(loss.to_json().stringify())
  println("quadratic boundary facets: \{boundary.mesh().elements().length()}")
}
