///|
fn example() -> @gmsh.Mesh raise {
  let points : Array[Array[Double]] = [
    [0, 0, 0],
    [1, 0, 0],
    [0, 1, 0],
    [0, 0, 1],
    [0.5, 0, -0.05],
    [0.5, 0.5, -0.1],
    [0, 0.5, -0.05],
    [0, 0, 0.5],
    [0, 0.5, 0.5],
    [0.5, 0, 0.5],
    [2, 2, 2],
  ]
  let nodes = points.mapi((i, xyz) => @gmsh.Node::{
    tag: if i == 10 {
      999
    } else {
      10 + i * 7
    },
    xyz,
    dim: -1,
    entity: 0,
    parameters: [],
  })
  let nodal = (
    name : String,
    step : Int,
    time : Double,
    values : Array[Double],
    missing : Bool,
  ) => {
    let entries = nodes
      .filter(n => !missing || n.tag != 45)
      .map(n => @gmsh.Datum::{ tag: n.tag, values, })
    @gmsh.Field::{
      location: "NodeData",
      strings: [name],
      reals: [time],
      integers: [step, values.length(), entries.length()],
      entries,
    }
  }
  @gmsh.mesh(
    nodes,
    [
      {
        tag: 201,
        kind: 11,
        nodes: [10, 17, 24, 31, 38, 45, 52, 59, 66, 73],
        entity: 0,
        physical: [99],
        extra: [],
      },
      {
        tag: 700,
        kind: 9,
        nodes: [10, 24, 17, 52, 45, 38],
        entity: 0,
        physical: [44],
        extra: [],
      },
      { tag: 900, kind: 15, nodes: [999], entity: 0, physical: [], extra: [], },
    ],
    fields=[
      nodal("温度", 0, 0.25, [300.0], false),
      nodal("velocity", 0, 0.25, [0.0, 0.0, -2.0], true),
      nodal("velocity", 3, 0.75, [0.0, 0.0, -4.0], false),
      {
        location: "ElementData",
        strings: ["volume_flow"],
        reals: [0.25],
        integers: [0, 3, 1],
        entries: [{ tag: 201, values: [0.0, 0.0, -3.0], }],
      },
      {
        location: "ElementData",
        strings: ["wall_flow"],
        reals: [0.25],
        integers: [0, 3, 1],
        entries: [{ tag: 700, values: [0.0, 0.0, -3.0], }],
      },
    ],
  )
}

///|
fn main raise {
  let source = example()
  let selected = source.subset([700, 900])
  let boundary = source.extract_boundary()
  let wall = boundary.mesh(allow_loss=true).select_physical(2, 44)
  let restored = @gmsh.decode(
    selected.compact().encode(version="4.1", binary=true),
  )
  let result : Json = {
    "frames": selected.field_frames().to_json(),
    "mixed_coverage": [
      for i in 0..<5 => selected.surface_field_coverage(i)
    ].to_json(),
    "count_only_partial": selected
    .surface_field_coverage(1, max_missing=0)
    .to_json(),
    "wall_coverage": [
      for i in 0..<5 => wall.surface_field_coverage(i)
    ].to_json(),
    "compact_binary_partial": restored.surface_field_coverage(1).to_json(),
    "provenance": boundary.report().to_json(),
    "chosen_frame2_flux": wall.integrate_surface_flux(2).to_json(),
    "explicit_cell_frame4_flux": wall.integrate_surface_flux(4).to_json(),
  }
  println(result.stringify())
}
