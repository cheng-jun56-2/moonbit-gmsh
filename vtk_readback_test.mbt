///|
fn vtk_bundle_fixture() -> (String, Json) raise {
  let text =
    #|# vtk DataFile Version 3.0
    #|hand-authored consistency fixture
    #|ASCII
    #|DATASET UNSTRUCTURED_GRID
    #|POINTS 2 double
    #|0 0 0 1 0 0
    #|CELLS 1 3
    #|2 0 1
    #|CELL_TYPES 1
    #|3
    #|POINT_DATA 2
    #|FIELD FieldData 2
    #|gmsh_value_0 1 2 double
    #|10 20
    #|gmsh_tag 1 2 int
    #|90 10
    #|CELL_DATA 1
    #|FIELD FieldData 2
    #|gmsh_value_1 3 1 double
    #|1 -2 3
    #|gmsh_tag 1 1 int
    #|201
  let audit = @json.parse(
    (
      #|{"source_version":"2.2","omitted_field_indices":[],"losses":["msh_field_headers_not_in_vtk"],"fields":[
      #|{"field":{"field_index":1,"name":"t","location":"ElementData","components":3,"time_step":2,"time":0.25,"entries":1},"value_array":"gmsh_value_1","strings":["t"],"reals":[0.25],"integers":[2,3,1]},
      #|{"field":{"field_index":0,"name":"t","location":"NodeData","components":1,"time_step":2,"time":0.25,"entries":2},"value_array":"gmsh_value_0","strings":["t"],"reals":[0.25],"integers":[2,1,2]}]}
    ),
  )
  (text, audit)
}

///|
test "VTK bundle readback binds authored values to original tags without a writer" {
  let (text, audit) = vtk_bundle_fixture()
  let readback = @gmsh.read_vtk_fields(@utf8.encode(text), audit)
  assert_eq(readback.points, 2)
  assert_eq(readback.cells, 1)
  assert_eq(readback.point_tags, [90, 10])
  assert_eq(readback.cell_tags, [201])
  assert_true(readback.has_point_tags && readback.has_cell_tags)
  assert_eq(readback.fields.map(f => f.field.field_index), [1, 0])
  assert_eq(readback.fields[0].values, [[1.0, -2.0, 3.0]])
  assert_eq(readback.fields[1].values, [[10.0], [20.0]])
  assert_eq(readback.fields.map(f => f.field.name), ["t", "t"])
}

///|
test "VTK bundle readback refuses an association alias mismatch" {
  let (_, audit) = vtk_bundle_fixture()
  let wrong =
    #|# vtk DataFile Version 3.0
    #|hand-authored wrong array
    #|ASCII
    #|DATASET UNSTRUCTURED_GRID
    #|POINTS 2 double
    #|0 0 0 1 0 0
    #|CELLS 1 3
    #|2 0 1
    #|CELL_TYPES 1
    #|3
    #|POINT_DATA 2
    #|FIELD FieldData 2
    #|gmsh_value_1 1 2 double
    #|10 20
    #|gmsh_tag 1 2 int
    #|90 10
  let rejected = try {
    let _ = @gmsh.read_vtk_fields(@utf8.encode(wrong), audit)
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}

///|
test "VTK bundle readback keeps selected zero tuples distinct from absent tags" {
  let text =
    #|# vtk DataFile Version 3.0
    #|empty stored field
    #|ASCII
    #|DATASET UNSTRUCTURED_GRID
    #|POINTS 0 double
    #|CELLS 0 0
    #|CELL_TYPES 0
    #|POINT_DATA 0
    #|FIELD FieldData 2
    #|gmsh_value_2 1 0 double
    #|gmsh_tag 1 0 int
  let audit = @json.parse(
    (
      #|{"source_version":"4.1","omitted_field_indices":[0,1],"losses":["msh_field_headers_not_in_vtk","other_field_sections_omitted"],"fields":[{"field":{"field_index":2,"name":"empty","location":"NodeData","components":1,"time_step":0,"entries":0},"value_array":"gmsh_value_2","strings":["empty"],"reals":[],"integers":[0,1,0]}]}
    ),
  )
  let readback = @gmsh.read_vtk_fields(@utf8.encode(text), audit)
  assert_true(readback.has_point_tags && !readback.has_cell_tags)
  assert_eq(readback.point_tags, [])
  assert_eq(readback.fields[0].values, [])
  assert_eq(readback.fields[0].field.time, None)
  assert_eq(readback.omitted_field_indices, [0, 1])
}
