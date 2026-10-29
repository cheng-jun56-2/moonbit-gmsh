///|
fn vm_inputs() -> (@gmsh.Mesh, Bytes, Json) raise {
  let source =
    #|$MeshFormat
    #|2.2 0 8
    #|$EndMeshFormat
    #|$PhysicalNames
    #|2
    #|3 44 "wedge"
    #|3 55 "tet10"
    #|$EndPhysicalNames
    #|$Nodes
    #|17
    #|90 0 0 0
    #|7 1 0 0
    #|50 0 1 0
    #|30 0 0 1
    #|20 1 0 1
    #|100 0 1 1
    #|201 2 0 0
    #|202 3 0 0
    #|203 2 1 0
    #|204 2 0 1
    #|205 2.5 0 0
    #|206 2.5 0.5 0
    #|207 2 0.5 0
    #|208 2 0 0.5
    #|209 2 0.5 0.5
    #|210 2.5 0 0.5
    #|2147483647 9 9 9
    #|$EndNodes
    #|$Elements
    #|2
    #|700 6 4 44 7 1 17 90 7 50 30 20 100
    #|8 11 4 55 8 1 22 201 202 203 204 205 206 207 208 209 210
    #|$EndElements
    #|$NodeData
    #|3
    #|"温度"
    #|""
    #|"node-extra"
    #|2
    #|0.25
    #|7.25
    #|5
    #|3
    #|1
    #|17
    #|31
    #|90
    #|2147483647 17
    #|210 16
    #|209 15
    #|208 14
    #|207 13
    #|206 12
    #|205 11
    #|204 10
    #|203 9
    #|202 8
    #|201 7
    #|100 6
    #|20 5
    #|30 4
    #|50 3
    #|7 2
    #|90 1
    #|$EndNodeData
    #|$NodeData
    #|2
    #|"velocity"
    #|"named-descriptor"
    #|0
    #|3
    #|5
    #|3
    #|17
    #|2147483647 16 32 -16
    #|210 15 30 -15
    #|209 14 28 -14
    #|208 13 26 -13
    #|207 12 24 -12
    #|206 11 22 -11
    #|205 10 20 -10
    #|204 9 18 -9
    #|203 8 16 -8
    #|202 7 14 -7
    #|201 6 12 -6
    #|100 5 10 -5
    #|20 4 8 -4
    #|30 3 6 -3
    #|50 2 4 -2
    #|7 1 2 -1
    #|90 0 0 0
    #|$EndNodeData
    #|$ElementData
    #|3
    #|"stress"
    #|""
    #|"cell-extra"
    #|1
    #|0.5
    #|5
    #|8
    #|9
    #|2
    #|0
    #|92
    #|8 9 8 7 6 5 4 3 2 1
    #|700 1 2 3 4 5 6 7 8 9
    #|$EndElementData
    #|$NodeData
    #|1
    #|"omitted"
    #|0
    #|3
    #|0
    #|1
    #|0
    #|$EndNodeData
    #|
  let vtk =
    #|# vtk DataFile Version 3.0
    #|independent saved export
    #|ASCII
    #|DATASET UNSTRUCTURED_GRID
    #|POINTS 17 double
    #|0 0 0
    #|1 0 0
    #|0 1 0
    #|0 0 1
    #|1 0 1
    #|0 1 1
    #|2 0 0
    #|3 0 0
    #|2 1 0
    #|2 0 1
    #|2.5 0 0
    #|2.5 0.5 0
    #|2 0.5 0
    #|2 0 0.5
    #|2 0.5 0.5
    #|2.5 0 0.5
    #|9 9 9
    #|CELLS 2 18
    #|6 0 2 1 3 5 4
    #|10 6 7 8 9 10 11 12 13 15 14
    #|CELL_TYPES 2
    #|13
    #|24
    #|POINT_DATA 17
    #|FIELD FieldData 3
    #|gmsh_value_0 1 17 double
    #|1
    #|2
    #|3
    #|4
    #|5
    #|6
    #|7
    #|8
    #|9
    #|10
    #|11
    #|12
    #|13
    #|14
    #|15
    #|16
    #|17
    #|gmsh_value_1 3 17 double
    #|0 0 0
    #|1 2 -1
    #|2 4 -2
    #|3 6 -3
    #|4 8 -4
    #|5 10 -5
    #|6 12 -6
    #|7 14 -7
    #|8 16 -8
    #|9 18 -9
    #|10 20 -10
    #|11 22 -11
    #|12 24 -12
    #|13 26 -13
    #|14 28 -14
    #|15 30 -15
    #|16 32 -16
    #|gmsh_tag 1 17 int
    #|90
    #|7
    #|50
    #|30
    #|20
    #|100
    #|201
    #|202
    #|203
    #|204
    #|205
    #|206
    #|207
    #|208
    #|209
    #|210
    #|2147483647
    #|CELL_DATA 2
    #|FIELD FieldData 2
    #|gmsh_value_2 9 2 double
    #|1 2 3 4 5 6 7 8 9
    #|9 8 7 6 5 4 3 2 1
    #|gmsh_tag 1 2 int
    #|700
    #|8
    #|
  let audit =
    #|{
    #|  "fields": [
    #|    {
    #|      "field": {
    #|        "field_index": 2,
    #|        "name": "stress",
    #|        "location": "ElementData",
    #|        "components": 9,
    #|        "time_step": 8,
    #|        "entries": 2,
    #|        "time": 0.5,
    #|        "partition": 0
    #|      },
    #|      "value_array": "gmsh_value_2",
    #|      "strings": [
    #|        "stress",
    #|        "",
    #|        "cell-extra"
    #|      ],
    #|      "reals": [
    #|        0.5
    #|      ],
    #|      "integers": [
    #|        8,
    #|        9,
    #|        2,
    #|        0,
    #|        92
    #|      ]
    #|    },
    #|    {
    #|      "field": {
    #|        "field_index": 0,
    #|        "name": "温度",
    #|        "location": "NodeData",
    #|        "components": 1,
    #|        "time_step": 3,
    #|        "entries": 17,
    #|        "time": 0.25,
    #|        "partition": 31
    #|      },
    #|      "value_array": "gmsh_value_0",
    #|      "strings": [
    #|        "温度",
    #|        "",
    #|        "node-extra"
    #|      ],
    #|      "reals": [
    #|        0.25,
    #|        7.25
    #|      ],
    #|      "integers": [
    #|        3,
    #|        1,
    #|        17,
    #|        31,
    #|        90
    #|      ]
    #|    },
    #|    {
    #|      "field": {
    #|        "field_index": 1,
    #|        "name": "velocity",
    #|        "location": "NodeData",
    #|        "components": 3,
    #|        "time_step": 5,
    #|        "entries": 17,
    #|        "interpolation_scheme": "named-descriptor"
    #|      },
    #|      "value_array": "gmsh_value_1",
    #|      "strings": [
    #|        "velocity",
    #|        "named-descriptor"
    #|      ],
    #|      "reals": [],
    #|      "integers": [
    #|        5,
    #|        3,
    #|        17
    #|      ]
    #|    }
    #|  ],
    #|  "source_version": "2.2",
    #|  "omitted_field_indices": [
    #|    3
    #|  ],
    #|  "losses": [
    #|    "msh_field_headers_not_in_vtk",
    #|    "other_field_sections_omitted",
    #|    "mesh_metadata_omitted"
    #|  ]
    #|}
    #|
  (@gmsh.decode(@utf8.encode(source)), @utf8.encode(vtk), @json.parse(audit))
}

///|
test "vtk mesh compare complete saved geometry and outlet roles" {
  let (source, data, audit) = vm_inputs()
  let result = source.verify_vtk_mesh(data, audit)
  assert_eq(result.points, source.nodes().map(n => n.xyz))
  assert_eq(result.source_node_tags, source.nodes().map(n => n.tag))
  assert_eq(result.source_element_tags, [700, 8])
  assert_eq(result.connectivity, [
    [0, 2, 1, 3, 5, 4],
    [6, 7, 8, 9, 10, 11, 12, 13, 15, 14],
  ])
  assert_eq(result.cell_types, [13, 24])
  assert_eq(result.fields.fields.map(f => f.field.field_index), [2, 0, 1])
  assert_eq(result.fields.fields[0].values, [
    [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0],
    [9.0, 8.0, 7.0, 6.0, 5.0, 4.0, 3.0, 2.0, 1.0],
  ])
}

///|
test "vtk mesh compare closes old geometry exclusion without changing old fields" {
  let (source, data, audit) = vm_inputs()
  for mode in 0..<4 {
    let nodes = source.nodes()
    let elements = source.elements()
    match mode {
      0 => nodes[16].xyz[2] = 9.5
      1 => elements[0].nodes[1] = 50
      2 => elements[0] = { ..elements[0], kind: 9, }
      _ => elements[0] = { ..elements[0], kind: 15, nodes: [90], }
    }
    let other = @gmsh.mesh(nodes, elements, fields=source.fields())
    ignore(other.verify_vtk_fields(data, audit))
    let rejected = try {
      ignore(other.verify_vtk_mesh(data, audit))
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
  let nodes = source.nodes()
  nodes[0].xyz[0] = -0.0
  let signed_zero = @gmsh.mesh(nodes, source.elements(), fields=source.fields())
  ignore(signed_zero.verify_vtk_mesh(data, audit))
}

///|
test "vtk mesh compare all result buffers owned" {
  let (source, data, audit) = vm_inputs()
  let original_fields = source.fields().to_json()
  let original_audit = audit.stringify()
  let first = source.verify_vtk_mesh(data, audit)
  let second = source.verify_vtk_mesh(data, audit)
  let before = second.to_json()
  first.points[0][0] = 99.0
  first.connectivity[0][0] = 16
  first.cell_types[0] = 99
  first.source_node_tags[0] = 999
  first.source_element_tags[0] = 999
  first.fields.point_tags[0] = 999
  first.fields.cell_tags[0] = 999
  first.fields.fields[0].values[0][0] = 99.0
  first.fields.losses[0] = "changed"
  assert_eq(source.verify_vtk_mesh(data, audit).to_json(), before)
  assert_eq(second.to_json(), before)
  assert_eq(source.fields().to_json(), original_fields)
  assert_eq(audit.stringify(), original_audit)
}

///|
test "vtk mesh compare absent association tags remain explicit losses" {
  let source = @gmsh.mesh(
    [{ tag: 7, xyz: [1.0, 2.0, 3.0], dim: -1, entity: 0, parameters: [], }],
    [{ tag: 50, kind: 15, nodes: [7], entity: 0, physical: [], extra: [], }],
    fields=[
      {
        location: "ElementData",
        strings: ["cell"],
        reals: [],
        integers: [0, 3, 1],
        entries: [{ tag: 50, values: [4.0, 5.0, 6.0], }],
      },
    ],
  )
  let data = @utf8.encode(
    "# vtk DataFile Version 3.0\nmanual\nASCII\nDATASET UNSTRUCTURED_GRID\nPOINTS 1 double\n1 2 3\nCELLS 1 2\n1 0\nCELL_TYPES 1\n1\nCELL_DATA 1\nFIELD FieldData 2\ngmsh_value_0 3 1 double\n4 5 6\ngmsh_tag 1 1 int\n50\n",
  )
  let audit : Json = {
    "source_version": "2.2",
    "omitted_field_indices": [],
    "losses": [
      "msh_field_headers_not_in_vtk", "other_association_tags_not_in_vtk",
    ],
    "fields": [
      {
        "field": {
          "field_index": 0,
          "name": "cell",
          "location": "ElementData",
          "components": 3,
          "time_step": 0,
          "entries": 1,
        },
        "value_array": "gmsh_value_0",
        "strings": ["cell"],
        "reals": [],
        "integers": [0, 3, 1],
      },
    ],
  }
  let result = source.verify_vtk_mesh(data, audit)
  assert_true(!result.fields.has_point_tags)
  assert_eq(result.fields.point_tags, [])
  assert_eq(result.source_node_tags, [7])
  assert_true(
    result.fields.losses.contains("other_association_tags_not_in_vtk"),
  )
  assert_eq(result.connectivity, [[0]])
}

///|
test "vtk mesh compare selected zero tuples retain empty profile" {
  let source = @gmsh.mesh([], [], fields=[
    {
      location: "NodeData",
      strings: ["empty"],
      reals: [],
      integers: [0, 1, 0],
      entries: [],
    },
  ])
  let data = @utf8.encode(
    "# vtk DataFile Version 3.0\nempty\nASCII\nDATASET UNSTRUCTURED_GRID\nPOINTS 0 double\nCELLS 0 0\nCELL_TYPES 0\nPOINT_DATA 0\nFIELD FieldData 2\ngmsh_value_0 1 0 double\ngmsh_tag 1 0 int\n",
  )
  let audit : Json = {
    "source_version": "2.2",
    "omitted_field_indices": [],
    "losses": ["msh_field_headers_not_in_vtk"],
    "fields": [
      {
        "field": {
          "field_index": 0,
          "name": "empty",
          "location": "NodeData",
          "components": 1,
          "time_step": 0,
          "entries": 0,
        },
        "value_array": "gmsh_value_0",
        "strings": ["empty"],
        "reals": [],
        "integers": [0, 1, 0],
      },
    ],
  }
  let result = source.verify_vtk_mesh(data, audit)
  assert_eq(result.points, [])
  assert_eq(result.connectivity, [])
  assert_eq(result.cell_types, [])
  assert_true(result.fields.has_point_tags)
  assert_true(!result.fields.has_cell_tags)
}
