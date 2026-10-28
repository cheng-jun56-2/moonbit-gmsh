///|
fn main raise {
  let nodes : Array[@gmsh.Node] = [
    { tag: 50, xyz: [0.0, 0.0, 0.0], dim: -1, entity: 0, parameters: [], },
    { tag: 10, xyz: [1.0, 0.0, 0.0], dim: -1, entity: 0, parameters: [], },
    { tag: 90, xyz: [0.0, 1.0, 0.0], dim: -1, entity: 0, parameters: [], },
    { tag: 999, xyz: [2.0, 2.0, 2.0], dim: -1, entity: 0, parameters: [], },
  ]
  let source = @gmsh.mesh(
    nodes,
    [
      {
        tag: 201,
        kind: 2,
        nodes: [50, 10, 90],
        entity: 7,
        physical: [44],
        extra: [],
      },
    ],
    fields=[
      {
        location: "NodeData",
        strings: ["温度"],
        reals: [0.75],
        integers: [3, 1, 4],
        entries: [
          { tag: 999, values: [400.0], },
          { tag: 90, values: [300.0], },
          { tag: 10, values: [200.0], },
          { tag: 50, values: [100.0], },
        ],
      },
      {
        location: "ElementData",
        strings: ["cell traction"],
        reals: [1.25],
        integers: [5, 3, 1],
        entries: [{ tag: 201, values: [1.0, 2.0, 3.0], }],
      },
    ],
  )
  for field_index in 0..<2 {
    println(
      source.vtk_field(field_index, allow_loss=true).to_json().stringify(),
    )
  }
}
