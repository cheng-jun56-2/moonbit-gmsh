///|
fn example(reverse : Bool) -> @gmsh.Mesh raise {
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
  let pressure = (step : Int, factor : Double) => @gmsh.Field::{
    location: "NodeData",
    strings: ["pressure"],
    reals: [0.25 + 0.25 * step.to_double()],
    integers: [step, 1, 6],
    entries: nodes.map(n => { tag: n.tag, values: [factor * (1.0 + n.xyz[0])], }),
  }
  @gmsh.mesh(
    nodes,
    [
      {
        tag: 201,
        kind: 9,
        nodes: if reverse {
          [10, 24, 17, 45, 38, 31]
        } else {
          [10, 17, 24, 31, 38, 45]
        },
        entity: 7,
        physical: [44],
        extra: [],
      },
    ],
    fields=[
      pressure(0, 1.0),
      pressure(1, 2.0),
      {
        location: "ElementData",
        strings: ["constant_pressure"],
        reals: [0.25],
        integers: [0, 1, 1],
        entries: [{ tag: 201, values: [2.0], }],
      },
    ],
  )
}

///|
fn main raise {
  for reverse in [false, true] {
    let wall = example(reverse).select_physical(2, 44)
    let scalar = wall.integrate_surface_field(0)
    let normal = wall.integrate_surface_normal_field(0)
    let mean = scalar.integral[0] / scalar.surface_measure
    let result : Json = {
      "reversed": reverse.to_json(),
      "frames": wall.field_frames().to_json(),
      "coverage": wall.surface_field_coverage(0).to_json(),
      "normal_frames": [
        for i in 0..<3 => wall.integrate_surface_normal_field(i)
      ].to_json(),
      "scalar_area_integral": scalar.to_json(),
      "mean_times_area_vector": normal.area_vector.map(x => mean * x).to_json(),
      "binary_frame0": @gmsh.decode(wall.encode(version="4.1", binary=true))
      .integrate_surface_normal_field(0)
      .to_json(),
    }
    println(result.stringify())
  }
}
