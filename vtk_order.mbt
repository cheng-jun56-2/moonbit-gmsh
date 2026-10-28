///|
/// Raw Gmsh -> VTK9.3/meshio5.3.5. Apply at the VTK outlet only.
fn vtk_nodes(e : Element) -> Array[Int] {
  let order = match e.kind {
    6 => [0, 2, 1, 3, 5, 4]
    11 => [0, 1, 2, 3, 4, 5, 6, 7, 9, 8]
    12 =>
      [
        0, 1, 2, 3, 4, 5, 6, 7, 8, 11, 13, 9, 16, 18, 19, 17, 10, 12, 14, 15, 22,
        23, 21, 24, 20, 25, 26,
      ]
    17 => [0, 1, 2, 3, 4, 5, 6, 7, 8, 11, 13, 9, 16, 18, 19, 17, 10, 12, 14, 15]
    _ => return e.nodes
  }
  order.map(i => e.nodes[i])
}
