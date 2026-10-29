///|
fn recipient_input() -> @gmsh.Mesh raise {
  let text =
    #|$MeshFormat
    #|2.2 0 8
    #|$EndMeshFormat
    #|$PhysicalNames
    #|2
    #|2 44 "wall"
    #|1 9 "edge"
    #|$EndPhysicalNames
    #|$Nodes
    #|4
    #|50 0 3 0
    #|90 0 0 0
    #|10 2 0 0
    #|2147483647 9 9 9
    #|$EndNodes
    #|$Elements
    #|2
    #|201 2 4 44 7 1 17 90 10 50
    #|8 1 4 9 3 1 22 10 50
    #|$EndElements
    #|$NodeData
    #|3
    #|"温度"
    #|""
    #|"recipient-extra"
    #|2
    #|0.5
    #|9.25
    #|5
    #|2
    #|1
    #|4
    #|17
    #|91
    #|50 30
    #|90 10
    #|10 20
    #|2147483647 40
    #|$EndNodeData
    #|
  @gmsh.decode(@utf8.encode(text))
}

///|
fn donor_input() -> @gmsh.Mesh raise {
  let text =
    #|$MeshFormat
    #|4.1 0 8
    #|$EndMeshFormat
    #|$PhysicalNames
    #|2
    #|2 88 "other surface"
    #|1 99 "other curve"
    #|$EndPhysicalNames
    #|$Entities
    #|0 1 1 0
    #|80 0 0 0 9 9 9 1 99 0
    #|70 0 0 0 9 9 9 1 88 1 80
    #|$EndEntities
    #|$Nodes
    #|2 4 10 2147483647
    #|1 80 0 1
    #|2147483647
    #|9 9 9
    #|2 70 1 3
    #|10 50 90
    #|2 0 0 2 0
    #|0 3 0 0 3
    #|0 0 0 0 0
    #|$EndNodes
    #|$Elements
    #|2 2 8 201
    #|1 80 1 1
    #|8 10 50
    #|2 70 2 1
    #|201 90 10 50
    #|$EndElements
    #|$NodeData
    #|3
    #|"温度"
    #|"named-descriptor"
    #|"donor-extra"
    #|2
    #|0.5
    #|7.25
    #|5
    #|2
    #|1
    #|2
    #|31
    #|92
    #|90 100
    #|50 300
    #|$EndNodeData
    #|$NodeData
    #|1
    #|"velocity"
    #|0
    #|3
    #|7
    #|3
    #|4
    #|2147483647 9 8 7
    #|10 2 3 4
    #|50 5 6 7
    #|90 1 2 3
    #|$EndNodeData
    #|$ElementData
    #|3
    #|"stress"
    #|""
    #|"cell-extra"
    #|2
    #|0
    #|1.25
    #|5
    #|3
    #|9
    #|2
    #|0
    #|93
    #|8 9 8 7 6 5 4 3 2 1
    #|201 1 2 3 4 5 6 7 8 9
    #|$EndElementData
    #|$NodeData
    #|1
    #|"empty"
    #|0
    #|3
    #|8
    #|1
    #|0
    #|$EndNodeData
    #|
  @gmsh.decode(@utf8.encode(text))
}

///|
fn snapshot(m : @gmsh.Mesh) -> Json {
  {
    "source_version": m.source_version().to_json(),
    "nodes": m.nodes().to_json(),
    "elements": m.elements().to_json(),
    "entities": m.entities().to_json(),
    "physical_names": m.physical_names().to_json(),
    "unknown_sections": m.unknown_sections().to_json(),
    "fields": m.fields().to_json(),
  }
}

///|
/// Actual self-authored public-package receiver, not third-party adoption.
fn main raise {
  let recipient = recipient_input()
  let donor = donor_input()
  let before_recipient = snapshot(recipient)
  let before_donor = snapshot(donor)
  let indices = [2, 0, 1, 3]
  let original_request = indices.copy()
  let received = recipient.append_fields(donor, indices)
  let expected = [
    recipient.fields()[0],
    donor.fields()[2],
    donor.fields()[0],
    donor.fields()[1],
    donor.fields()[3],
  ]
  guard received.fields().to_json() == expected.to_json() &&
    received.nodes().to_json() == recipient.nodes().to_json() &&
    received.elements().to_json() == recipient.elements().to_json() &&
    received.entities().to_json() == recipient.entities().to_json() &&
    received.physical_names().to_json() == recipient.physical_names().to_json() &&
    received.source_version() == recipient.source_version() else {
    raise Failure("append receiver complete result differs")
  }
  guard received.field_frames().map(f => f.field_index) == [0, 1, 2, 3, 4] &&
    received.field_frames().map(f => f.entries) == [4, 2, 2, 4, 0] &&
    received.fields()[1].entries[0].values ==
    [9.0, 8.0, 7.0, 6.0, 5.0, 4.0, 3.0, 2.0, 1.0] &&
    received.fields()[2].entries[0].values == [100.0] &&
    received.fields()[3].entries[0].values == [9.0, 8.0, 7.0] &&
    received.fields()[4].entries.is_empty() else {
    raise Failure("append receiver hand sections differ")
  }
  let before_result = snapshot(received)
  indices[0] = 1
  let taken = received.fields()
  taken[1].strings[0] = "changed"
  taken[1].entries[0].values[0] = 99.0
  guard snapshot(received) == before_result &&
    snapshot(recipient) == before_recipient &&
    snapshot(donor) == before_donor else {
    raise Failure("append receiver ownership differs")
  }
  let result : Json = {
    "evidence": "self-authored public-package receiver",
    "requested_donor_indices": original_request.to_json(),
    "received": snapshot(received),
    "source_unchanged": true,
    "physical_equivalence_certified": false,
  }
  println(result.stringify())
}
