///|
fn main raise {
  let nodes : Array[@gmsh.Node] = [
    [0.0, 0.0, 0.0],
    [1.0, 0.0, 0.0],
    [0.0, 1.0, 0.0],
    [0.0, 0.0, 1.0],
  ].mapi((i, xyz) => {
    tag: (i + 1) * 10,
    xyz,
    dim: -1,
    entity: 0,
    parameters: [],
  })
  let source = @gmsh.mesh(nodes, [
    {
      tag: 77,
      kind: 4,
      nodes: [10, 20, 30, 40],
      entity: 0,
      physical: [],
      extra: [],
    },
  ])
  let boundary = source.extract_boundary()
  println(boundary.report().to_json().stringify())
  let surface = boundary.mesh()
  let reread = @gmsh.decode(surface.encode(version="4.1", binary=true))
  println("boundary elements: \{reread.elements().length()}")
}
