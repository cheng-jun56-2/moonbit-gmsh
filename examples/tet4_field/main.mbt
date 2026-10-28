///|
/// Self-authored public-package receiver, not customer/deployment evidence.
fn main raise {
  let tags = [700, 999, 90, 2147483647, 10]
  let xyz = [
    [0.0, 3.0, 0.0],
    [9.0, 9.0, 9.0],
    [0.0, 0.0, 0.0],
    [0.0, 0.0, 4.0],
    [2.0, 0.0, 0.0],
  ]
  let nodes = tags.mapi((i, tag) => @gmsh.Node::{
    tag,
    xyz: xyz[i],
    dim: -1,
    entity: 0,
    parameters: [],
  })
  let datum_tags = [2147483647, 90, 999, 10, 700]
  let scalar = [13.0, 1.0, 123.0, 3.0, 7.0]
  let vector = [
    [0.0, 0.0, 4.0],
    [0.0, 0.0, 0.0],
    [9.0, 9.0, 9.0],
    [2.0, 0.0, 0.0],
    [0.0, 3.0, 0.0],
  ]
  let fields : Array[@gmsh.Field] = [
    for components in [1, 3, 9] => {
      {
        location: "NodeData",
        strings: [
          if components == 1 {
            "温度"
          } else {
            "components"
          },
          "",
          "raw extra",
        ],
        reals: [0.5, 7.25],
        integers: [2, components, 5, 17, 42],
        entries: datum_tags.mapi((i, tag) => {
          tag,
          values: if components == 3 {
            vector[i]
          } else {
            [
              for k in 1..<=components => k.to_double() * scalar[i]
            ]
          },
        }),
      }
    }
  ]
  fields.push({
    ..fields[0],
    entries: fields[0].entries.map(d => { ..d, values: [d.values[0] + 100.0], }),
  })
  fields.push({
    ..fields[0],
    strings: ["constant"],
    entries: datum_tags.map(tag => { tag, values: [-7.0], }),
  })
  let source = @gmsh.mesh(
    nodes,
    [
      {
        tag: 201,
        kind: 4,
        nodes: [90, 10, 700, 2147483647],
        entity: 0,
        physical: [],
        extra: [],
      },
    ],
    fields~,
  )
  let before = source.fields().to_json()
  let reference = [0.25, 0.125, 0.125]
  let received = [
    for index in 0..<4 => {
      source.evaluate_tet4_nodal_field(index, 201, reference)
    }
  ]
  guard received[0].values == [3.75] &&
    received[1].values == [0.5, 0.375, 0.5] &&
    received[2].values ==
    [3.75, 7.5, 11.25, 15.0, 18.75, 22.5, 26.25, 30.0, 33.75] &&
    received[3].values == [103.75] else {
    raise Failure("public TET4 receiver hand values differ")
  }
  for index, r in received {
    guard r.field.field_index == index &&
      r.element_tag == 201 &&
      r.element_type == 4 &&
      r.node_tags == [90, 10, 700, 2147483647] &&
      r.weights == [0.5, 0.25, 0.125, 0.125] &&
      r.reference == reference &&
      r.xyz == [0.5, 0.375, 0.5] &&
      r.strings == fields[index].strings &&
      r.reals == fields[index].reals &&
      r.integers == fields[index].integers &&
      r.node_xyz ==
      [[0.0, 0.0, 0.0], [2.0, 0.0, 0.0], [0.0, 3.0, 0.0], [0.0, 0.0, 4.0]] else {
      raise Failure("public TET4 receiver source witnesses differ")
    }
  }
  guard received[0].nodal_values == [[1.0], [3.0], [7.0], [13.0]] &&
    received[0].field.entries == 5 &&
    received[0].field.time == Some(0.5) &&
    received[0].field.partition == Some(17) &&
    received[3].field.name == received[0].field.name else {
    raise Failure("public TET4 receiver raw identity differs")
  }
  reference[0] = 0.5
  let probe = source.evaluate_tet4_nodal_field(0, 201, [0.25, 0.125, 0.125])
  probe.nodal_values[0][0] = 99.0
  probe.node_xyz[0][0] = 99.0
  probe.strings[0] = "changed"
  guard source.fields().to_json() == before &&
    received[0].reference == [0.25, 0.125, 0.125] else {
    raise Failure("public TET4 receiver ownership differs")
  }
  let result : Json = {
    "evidence": "self-authored public-package receiver",
    "evaluations": received.to_json(),
    "source_unchanged": true,
    "geometry_certified": false,
  }
  println(result.stringify())
}
