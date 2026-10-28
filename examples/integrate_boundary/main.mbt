///|
/// Self-authored curved wall with nodal heat flux and supplied global traction.
/// The result is a fixed-rule estimate, not a CAD/global-error certificate.
fn main raise {
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
  let volume : @gmsh.Element = {
    tag: 201,
    kind: 11,
    nodes: nodes.map(n => n.tag),
    entity: 0,
    physical: [99],
    extra: [],
  }
  let face : @gmsh.Element = {
    tag: 700,
    kind: 9,
    nodes: [10, 24, 17, 52, 45, 38],
    entity: 0,
    physical: [44],
    extra: [],
  }
  let heat : @gmsh.Field = {
    location: "NodeData",
    strings: ["heat_flux"],
    reals: [0.25],
    integers: [0, 1, 10],
    entries: nodes.map(n => {
      tag: n.tag,
      values: [2.0 + n.xyz[0] + 2.0 * n.xyz[1]],
    }),
  }
  let traction : @gmsh.Field = {
    location: "ElementData",
    strings: ["traction"],
    reals: [0.25],
    integers: [0, 3, 1],
    entries: [{ tag: 700, values: [0.0, 0.0, -5.0], }],
  }
  let source = @gmsh.mesh(
    nodes,
    [volume, face],
    names=[{ dim: 2, tag: 44, name: "heated_wall", }],
    fields=[heat, traction],
  )
  let boundary = source.extract_boundary()
  // Inspect every omission before explicitly requesting the derived mesh.
  println(boundary.report().to_json().stringify())
  let wall = boundary.mesh(allow_loss=true).select_physical(2, 44)
  println(wall.integrate_surface_field(0).to_json().stringify())
  println(wall.integrate_surface_field(1).to_json().stringify())
}
