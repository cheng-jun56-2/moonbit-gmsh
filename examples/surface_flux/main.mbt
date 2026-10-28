///|
fn example(reverse : Bool) -> @gmsh.Mesh raise {
  let points = [
    [0.0, 0.0, 0.0],
    [1.0, 0.0, 0.0],
    [0.0, 1.0, 0.0],
    [0.0, 0.0, 1.0],
    [0.5, 0.0, -0.05],
    [0.5, 0.5, -0.1],
    [0.0, 0.5, -0.05],
    [0.0, 0.0, 0.5],
    [0.0, 0.5, 0.5],
    [0.5, 0.0, 0.5],
  ]
  let nodes = points.mapi((i, xyz) => @gmsh.Node::{
    tag: 10 + i * 7,
    xyz,
    dim: -1,
    entity: 0,
    parameters: [],
  })
  let velocity = (step : Int, speed : Double) => @gmsh.Field::{
    location: "NodeData",
    strings: ["velocity"],
    reals: [0.25 + 0.25 * step.to_double()],
    integers: [step, 3, 10],
    entries: nodes.map(n => { tag: n.tag, values: [0.0, 0.0, -speed], }),
  }
  @gmsh.mesh(
    nodes,
    [
      {
        tag: 201,
        kind: 11,
        nodes: nodes.map(n => n.tag),
        entity: 0,
        physical: [99],
        extra: [],
      },
      {
        tag: 700,
        kind: 9,
        nodes: if reverse {
          [10, 17, 24, 38, 45, 52]
        } else {
          [10, 24, 17, 52, 45, 38]
        },
        entity: 0,
        physical: [44],
        extra: [],
      },
    ],
    fields=[velocity(0, 2.0), velocity(1, 4.0)],
  )
}

///|
fn main raise {
  for reverse in [false, true] {
    let boundary = example(reverse).extract_boundary()
    let wall = boundary.mesh(allow_loss=true).select_physical(2, 44)
    println(
      boundary
      .orientation_report()
      .filter(o => o.element == 700)
      .to_json()
      .stringify(),
    )
    println(wall.integrate_surface_flux(0).to_json().stringify())
    println(wall.integrate_surface_flux(1).to_json().stringify())
    println(wall.compact().integrate_surface_flux(0).to_json().stringify())
  }
}
