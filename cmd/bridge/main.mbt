///|
extern "js" fn fail_string(message : String) -> String =
  #| (message) => { throw new Error(message); }

///|
extern "js" fn fail_bytes(message : String) -> Bytes =
  #| (message) => { throw new Error(message); }

///|
fn object(text : String) -> Map[String, Json] raise {
  if text.length() > 8000000 {
    raise Failure("options exceed 8M characters")
  }
  match @json.parse(text) {
    Object(o) => o
    _ => raise Failure("expected JSON object")
  }
}

///|
fn[T : @json.FromJson] req(o : Map[String, Json], key : String) -> T raise {
  match o.get(key) {
    Some(j) => @json.from_json(j)
    None => raise Failure("missing option: " + key)
  }
}

///|
fn[T : @json.FromJson] opt(
  o : Map[String, Json],
  key : String,
  fallback : T,
) -> T raise {
  match o.get(key) {
    Some(j) => @json.from_json(j)
    None => fallback
  }
}

///|
fn dict(j : Json) -> Map[String, Json] raise {
  match j {
    Object(o) => o
    _ => raise Failure("expected object in array")
  }
}

///|
// FromJson[Int] may truncate fractional numbers: IDs/budgets must be exact.
fn integer(j : Json) -> Int raise {
  let x : Double = @json.from_json(j)
  if x != x || x < -2147483648.0 || x > 2147483647.0 || x != x.floor() {
    raise Failure("expected signed 32-bit integer")
  }
  x.to_int()
}

///|
fn req_int(o : Map[String, Json], key : String) -> Int raise {
  integer(req(o, key))
}

///|
fn opt_int(o : Map[String, Json], key : String, fallback : Int) -> Int raise {
  match o.get(key) {
    Some(j) => integer(j)
    None => fallback
  }
}

///|
fn ints(
  o : Map[String, Json],
  key : String,
  required? : Bool = false,
) -> Array[Int] raise {
  let values : Array[Json] = if required {
    req(o, key)
  } else {
    opt(o, key, [])
  }
  values.map(integer)
}

///|
fn model(o : Map[String, Json]) -> @lib.Mesh raise {
  let ns : Array[Json] = req(o, "nodes")
  let es : Array[Json] = req(o, "elements")
  let ents : Array[Json] = opt(o, "entities", [])
  let names : Array[Json] = opt(o, "names", [])
  let fs : Array[Json] = opt(o, "fields", [])
  let unknown : Array[Json] = opt(o, "unknown", [])
  let nodes = ns.map(j => {
    let x = dict(j)
    @lib.Node::{
      tag: req_int(x, "tag"),
      xyz: req(x, "xyz"),
      dim: opt_int(x, "dim", -1),
      entity: opt_int(x, "entity", 0),
      parameters: opt(x, "parameters", []),
    }
  })
  let elements = es.map(j => {
    let x = dict(j)
    @lib.Element::{
      tag: req_int(x, "tag"),
      kind: req_int(x, "kind"),
      nodes: ints(x, "nodes", required=true),
      entity: opt_int(x, "entity", 0),
      physical: ints(x, "physical"),
      extra: ints(x, "extra"),
    }
  })
  let entities = ents.map(j => {
    let x = dict(j)
    @lib.Entity::{
      dim: req_int(x, "dim"),
      tag: req_int(x, "tag"),
      bounds: req(x, "bounds"),
      physical: ints(x, "physical"),
      boundary: ints(x, "boundary"),
    }
  })
  let names = names.map(j => {
    let x = dict(j)
    @lib.PhysicalName::{
      dim: req_int(x, "dim"),
      tag: req_int(x, "tag"),
      name: req(x, "name"),
    }
  })
  let fields = fs.map(j => {
    let x = dict(j)
    let data : Array[Json] = req(x, "entries")
    @lib.Field::{
      location: req(x, "location"),
      strings: req(x, "strings"),
      reals: req(x, "reals"),
      integers: ints(x, "integers", required=true),
      entries: data.map(j => {
        let d = dict(j)
        @lib.Datum::{ tag: req_int(d, "tag"), values: req(d, "values"), }
      }),
    }
  })
  let sections = unknown.map(j => {
    let x = dict(j)
    @lib.Section::{ name: req(x, "name"), body: req(x, "body"), }
  })
  @lib.mesh(
    nodes,
    elements,
    entities~,
    names~,
    fields~,
    unknown=sections,
    version=opt(o, "source_version", "2.2"),
  )
}

///|
fn encode(m : @lib.Mesh, o : Map[String, Json]) -> Bytes raise {
  let m = if opt(o, "drop_unknown", false) { m.without_unknown() } else { m }
  m.encode(
    version=opt(o, "version", m.source_version()),
    binary=opt(o, "binary", false),
    little=opt(o, "little", true),
    size_width=opt_int(o, "size_width", 8),
    allow_loss=opt(o, "allow_loss", false),
  )
}

///|
fn do_report(data : Bytes, options : String) -> String raise {
  let o = object(options)
  let m = @lib.decode(data)
  let command : String = opt(o, "command", "inspect")
  let result : Json = match command {
    "field-records" =>
      m
      .field_records(
        req(o, "location"),
        req_int(o, "tag"),
        ints(o, "field_indices", required=true),
      )
      .to_json()
    "evaluate-tet4-field" =>
      m
      .evaluate_tet4_nodal_field(
        req_int(o, "field_index"),
        req_int(o, "element_tag"),
        req(o, "reference"),
      )
      .to_json()
    "field-frames" => m.field_frames().to_json()
    "surface-field-coverage" =>
      m
      .surface_field_coverage(
        req_int(o, "field_index"),
        max_missing=opt_int(o, "max_missing", 1000),
      )
      .to_json()
    "inspect" =>
      {
        "version": m.source_version().to_json(),
        "nodes": m.nodes().length().to_json(),
        "elements": m.elements().length().to_json(),
        "entities": m.entities().length().to_json(),
        "physical_names": m.physical_names().to_json(),
        "fields": m.fields().map(f => f.strings).to_json(),
        "unknown_sections": m.unknown_sections().map(s => s.name).to_json(),
      }
    "dump" =>
      {
        "version": m.source_version().to_json(),
        "nodes": m.nodes().to_json(),
        "elements": m.elements().to_json(),
        "entities": m.entities().to_json(),
        "names": m.physical_names().to_json(),
        "fields": m.fields().to_json(),
        "unknown": m.unknown_sections().to_json(),
      }
    "validate" =>
      m.diagnostics(tolerance=opt(o, "tolerance", 1.0e-12)).to_json()
    "quality" =>
      m
      .quality(req_int(o, "tag"), tolerance=opt(o, "tolerance", 1.0e-12))
      .to_json()
    "surface-flux-breakdown" =>
      m
      .surface_flux_breakdown(
        req_int(o, "field_index"),
        max_samples=opt_int(o, "max_samples", 1000000),
        max_elements=opt_int(o, "max_elements", 10000),
      )
      .to_json()
    "integrate-surface-normal-field" =>
      m
      .integrate_surface_normal_field(
        req_int(o, "field_index"),
        max_samples=opt_int(o, "max_samples", 1000000),
      )
      .to_json()
    "integrate-surface-flux" =>
      m
      .integrate_surface_flux(
        req_int(o, "field_index"),
        max_samples=opt_int(o, "max_samples", 1000000),
      )
      .to_json()
    "integrate-surface-field" =>
      m
      .integrate_surface_field(
        req_int(o, "field_index"),
        max_samples=opt_int(o, "max_samples", 1000000),
      )
      .to_json()
    "sample-gauss" =>
      m
      .sample_gauss_jacobians(
        req_int(o, "tag"),
        reference_normal=opt(o, "reference_normal", []),
      )
      .to_json()
    "boundary-orientations" =>
      m
      .extract_boundary(dimension=opt_int(o, "dimension", -1))
      .orientation_report()
      .to_json()
    "audited-obj" | "audited-stl" => {
      let policy = if opt(o, "permissive", false) {
        @lib.PermissiveWithAudit
      } else {
        @lib.Strict
      }
      let (text, loss) = if command == "audited-obj" {
        m.export_to_obj(policy)
      } else {
        m.export_to_stl(policy)
      }
      { "text": text.to_json(), "loss_report": loss.to_json() }
    }
    "topology" => m.topology(dimension=opt_int(o, "dimension", -1)).to_json()
    "boundary" => {
      let m = if opt(o, "drop_unknown", false) {
        m.without_unknown()
      } else {
        m
      }
      m
      .extract_boundary(
        dimension=opt_int(o, "dimension", -1),
        max_facets=opt_int(o, "max_facets", 1000000),
      )
      .report()
      .to_json()
    }
    "coverage" =>
      m
      .extract_boundary(
        dimension=opt_int(o, "dimension", -1),
        max_facets=opt_int(o, "max_facets", 1000000),
      )
      .coverage(required_groups=ints(o, "required_groups"))
      .to_json()
    "components" => m.components().to_json()
    "vtk" => { "text": m.vtk(allow_loss=opt(o, "allow_loss", false)).to_json() }
    "vtk-field" =>
      m
      .vtk_field(
        req_int(o, "field_index"),
        allow_loss=opt(o, "allow_loss", false),
      )
      .to_json()
    "vtk-fields" =>
      m
      .vtk_fields(
        ints(o, "field_indices", required=true),
        allow_loss=opt(o, "allow_loss", false),
      )
      .to_json()
    "obj" => { "text": m.obj(allow_loss=opt(o, "allow_loss", false)).to_json() }
    _ => raise Failure("unknown report command: " + command)
  }
  result.stringify()
}

///|
pub fn report(data : Bytes, options : String) -> String {
  do_report(data, options) catch {
    e => fail_string(@debug.to_string(e))
  }
}

///|
fn do_transform(data : Bytes, options : String) -> Bytes raise {
  let o = object(options)
  let m = @lib.decode(data)
  let m = if opt(o, "drop_unknown", false) { m.without_unknown() } else { m }
  let command : String = opt(o, "command", "copy")
  let m = match command {
    "copy" | "convert" => m
    "select-fields" => m.select_fields(ints(o, "field_indices", required=true))
    "subset" => m.subset(ints(o, "tags", required=true))
    "physical" =>
      m.select_physical(req_int(o, "dimension"), req_int(o, "group"))
    "physical-name" =>
      m.select_physical_name(req_int(o, "dimension"), req(o, "name"))
    "compact" => m.compact()
    "boundary-msh" =>
      m
      .extract_boundary(
        dimension=opt_int(o, "dimension", -1),
        max_facets=opt_int(o, "max_facets", 1000000),
      )
      .mesh(allow_loss=opt(o, "allow_loss", false))
    _ => raise Failure("unknown transform command: " + command)
  }
  encode(m, o)
}

///|
pub fn transform(data : Bytes, options : String) -> Bytes {
  do_transform(data, options) catch {
    e => fail_bytes(@debug.to_string(e))
  }
}

///|
pub fn new_file(options : String) -> Bytes {
  try {
    let o = object(options)
    encode(model(o), o)
  } catch {
    e => fail_bytes(@debug.to_string(e))
  }
}

///|
pub fn append_fields(data : Bytes, donor : Bytes, options : String) -> Bytes {
  try {
    let o = object(options)
    let recipient = @lib.decode(data)
    let source = @lib.decode(donor)
    let drop = opt(o, "drop_unknown", false)
    let recipient = if drop { recipient.without_unknown() } else { recipient }
    let source = if drop { source.without_unknown() } else { source }
    encode(
      recipient.append_fields(source, ints(o, "field_indices", required=true)),
      o,
    )
  } catch {
    e => fail_bytes(@debug.to_string(e))
  }
}

///|
pub fn read_vtk_fields(data : Bytes, audit : String) -> String {
  @lib.read_vtk_fields(data, @json.parse(audit)).to_json().stringify() catch {
    e => fail_string(@debug.to_string(e))
  }
}

///|
pub fn verify_vtk_fields(
  source : Bytes,
  data : Bytes,
  audit : String,
) -> String {
  @lib.decode(source)
  .verify_vtk_fields(data, @json.parse(audit))
  .to_json()
  .stringify() catch {
    e => fail_string(@debug.to_string(e))
  }
}

///|
pub fn verify_vtk_mesh(source : Bytes, data : Bytes, audit : String) -> String {
  @lib.decode(source)
  .verify_vtk_mesh(data, @json.parse(audit))
  .to_json()
  .stringify() catch {
    e => fail_string(@debug.to_string(e))
  }
}

///|
fn main {

}
