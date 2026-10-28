///|
fn vtk_comparison_source(
  value? : Double = 10.0,
  extra? : Bool = false,
  omitted? : Bool = false,
) -> @gmsh.Mesh raise {
  let fields : Array[@gmsh.Field] = [
    {
      location: "NodeData",
      strings: if extra {
        ["t", "", "source-only-extra"]
      } else {
        ["t"]
      },
      reals: [0.25],
      integers: [2, 1, 2],
      entries: [{ tag: 10, values: [20.0], }, { tag: 90, values: [value], }],
    },
    {
      location: "ElementData",
      strings: ["t"],
      reals: [0.25],
      integers: [2, 3, 1],
      entries: [{ tag: 201, values: [1.0, -2.0, 3.0], }],
    },
  ]
  if omitted {
    fields.push({
      location: "NodeData",
      strings: ["t"],
      reals: [0.25],
      integers: [2, 1, 0],
      entries: [],
    })
  }
  @gmsh.mesh(
    [
      { tag: 90, xyz: [0.0, 0.0, 0.0], dim: -1, entity: 0, parameters: [], },
      { tag: 10, xyz: [1.0, 0.0, 0.0], dim: -1, entity: 0, parameters: [], },
    ],
    [
      {
        tag: 201,
        kind: 1,
        nodes: [90, 10],
        entity: 0,
        physical: [],
        extra: [],
      },
    ],
    fields~,
  )
}

///|
test "VTK source comparison matches tagged values in arbitrary source datum order" {
  let (text, audit) = vtk_bundle_fixture()
  let source = vtk_comparison_source()
  let before = source.fields().to_json()
  let saved = source.verify_vtk_fields(@utf8.encode(text), audit)
  assert_eq(saved.fields.map(f => f.field.field_index), [1, 0])
  assert_eq(saved.fields[1].values, [[10.0], [20.0]])
  saved.fields[1].values[0][0] = 99.0
  assert_eq(source.fields().to_json(), before)
}

///|
test "VTK source comparison rejects coherent values and complete raw-head differences" {
  let (text, audit) = vtk_bundle_fixture()
  for
    source in [
      vtk_comparison_source(value=11.0),
      vtk_comparison_source(extra=true),
    ] {
    let before = source.fields().to_json()
    let rejected = try {
      let _ = source.verify_vtk_fields(@utf8.encode(text), audit)
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
    assert_eq(source.fields().to_json(), before)
  }
}

///|
test "VTK source comparison checks omitted source sections and source version" {
  let (text, audit) = vtk_bundle_fixture()
  let source = vtk_comparison_source()
  let other_version = @gmsh.mesh(
    source.nodes(),
    source.elements(),
    fields=source.fields(),
    version="4.1",
  )
  for changed in [vtk_comparison_source(omitted=true), other_version] {
    let rejected = try {
      let _ = changed.verify_vtk_fields(@utf8.encode(text), audit)
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}

///|
test "VTK source comparison accepts an explicit empty source field without time" {
  let text =
    #|# vtk DataFile Version 3.0
    #|new empty equality fixture
    #|ASCII
    #|DATASET UNSTRUCTURED_GRID
    #|POINTS 0 double
    #|CELLS 0 0
    #|CELL_TYPES 0
    #|POINT_DATA 0
    #|FIELD FieldData 2
    #|gmsh_value_0 1 0 double
    #|gmsh_tag 1 0 int
  let audit : Json = {
    "source_version": "2.2",
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
    "omitted_field_indices": [],
    "losses": ["msh_field_headers_not_in_vtk"],
  }
  let source = @gmsh.mesh([], [], fields=[
    {
      location: "NodeData",
      strings: ["empty"],
      reals: [],
      integers: [0, 1, 0],
      entries: [],
    },
  ])
  let saved = source.verify_vtk_fields(@utf8.encode(text), audit)
  assert_true(saved.has_point_tags && !saved.has_cell_tags)
  assert_eq(saved.fields[0].values, [])
}
