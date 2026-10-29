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
/// Actual self-authored receiver of three independent originals, not adoption.
fn main raise {
  let (source, data, audit) = vm_inputs()
  let before = source.fields().to_json()
  let audit_before = audit.stringify()
  let first = source.verify_vtk_mesh(data, audit)
  let full = first.to_json()
  let second = source.verify_vtk_mesh(data, audit)
  first.points[0][0] = 99.0
  first.connectivity[0][0] = 16
  first.cell_types[0] = 99
  first.source_node_tags[0] = 999
  first.source_element_tags[0] = 999
  first.fields.fields[0].values[0][0] = 99.0
  guard second.to_json() == full &&
    source.fields().to_json() == before &&
    audit.stringify() == audit_before &&
    source.nodes()[0].xyz == [0.0, 0.0, 0.0] else {
    raise Failure("VTK mesh receiver ownership differs")
  }
  let result : Json = {
    "evidence": "self-authored public saved-mesh receiver",
    "readback": full,
    "ownership_isolated": true,
    "geometric_validity_certified": false,
  }
  println(result.stringify())
}
