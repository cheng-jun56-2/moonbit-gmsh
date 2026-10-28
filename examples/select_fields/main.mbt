///|
fn main raise {
  let points = [
    [0.0, 0.0, 0.0],
    [1.0, 0.0, 1.0],
    [0.0, 1.0, 1.0],
    [0.5, 0.0, 0.25],
    [0.5, 0.5, 0.5],
    [0.0, 0.5, 0.25],
  ]
  let nodes = points.mapi((i, xyz) => @gmsh.Node::{
    tag: 10 + i * 7,
    xyz,
    dim: -1,
    entity: 0,
    parameters: [],
  })
  let fields : Array[@gmsh.Field] = [
    for step in 0..<2 => {
      {
        location: "NodeData",
        strings: ["pressure"],
        reals: [0.25 + 0.25 * step.to_double()],
        integers: [step, 1, 6],
        entries: nodes.map(n => {
          tag: n.tag,
          values: [(step + 1).to_double() * (1.0 + n.xyz[0])],
        }),
      }
    }
  ]
  fields.push({
    location: "ElementData",
    strings: ["constant_pressure"],
    reals: [0.25],
    integers: [0, 1, 1],
    entries: [{ tag: 201, values: [2.0], }],
  })
  let source = @gmsh.mesh(
    nodes,
    [
      {
        tag: 201,
        kind: 9,
        nodes: nodes.map(n => n.tag),
        entity: 7,
        physical: [44],
        extra: [],
      },
    ],
    fields~,
  )
  let snapshot = source.select_fields([1])
  let result : Json = {
    "source_frames": source.field_frames().to_json(),
    "requested_source_indices": [1].to_json(),
    "output_frames": snapshot.field_frames().to_json(),
    "normal": snapshot.integrate_surface_normal_field(0).to_json(),
    "reordered_frames": source.select_fields([2, 1]).field_frames().to_json(),
    "geometry_only_fields": source.select_fields([]).fields().length().to_json(),
  }
  println(result.stringify())
}
