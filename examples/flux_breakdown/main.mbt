///|
fn audit_source(reverse : Bool) -> @gmsh.Mesh raise {
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
    let boundary = audit_source(reverse).extract_boundary()
    let skin = boundary.mesh(allow_loss=true)
    let binary = skin.compact().encode(version="4.1", binary=true)
    let frames = [
      skin.surface_flux_breakdown(0),
      skin.surface_flux_breakdown(1),
    ]
    let result : Json = {
      "reversed_explicit_face": reverse.to_json(),
      "provenance": boundary.report().to_json(),
      "orientations": boundary.orientation_report().to_json(),
      "current_elements": skin.elements().to_json(),
      "frames": frames.to_json(),
      "compact_binary_frame0": @gmsh.decode(binary)
      .surface_flux_breakdown(0)
      .to_json(),
      "physical44_frame0": skin
      .select_physical(2, 44)
      .surface_flux_breakdown(0)
      .to_json(),
    }
    println(result.stringify())
  }
}
