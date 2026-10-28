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
        strings: ["temperature"],
        reals: [1.5],
        integers: [4, 1, 4],
        entries: [
          { tag: 999, values: [400.0], },
          { tag: 90, values: [300.0], },
          { tag: 10, values: [200.0], },
          { tag: 50, values: [100.0], },
        ],
      },
      {
        location: "NodeData",
        strings: ["velocity"],
        reals: [1.5],
        integers: [4, 3, 4],
        entries: nodes.map(n => { tag: n.tag, values: n.xyz.map(x => x + 1.0), }),
      },
      {
        location: "ElementData",
        strings: ["stress"],
        reals: [1.5],
        integers: [4, 9, 1],
        entries: [
          { tag: 201, values: [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0], },
        ],
      },
    ],
  )
  for indices in [[2, 0, 1], [1, 0]] {
    println(source.vtk_fields(indices, allow_loss=true).to_json().stringify())
  }
}
