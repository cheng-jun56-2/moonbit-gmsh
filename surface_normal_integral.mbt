///|
/// Integral of one supplied scalar times the stored oriented area element.
/// This is not an automatic pressure-sign, unit, density or outward correction.
pub(all) struct SurfaceNormalIntegral {
  field_index : Int
  name : String
  location : String
  time_step : Int
  time : Double?
  elements : Int
  skipped_lower_dimension : Int
  samples : Int
  rules : Array[String]
  surface_measure : Double
  area_vector : Array[Double]
  normal_integral : Array[Double]
  zero_measure_samples : Int
  normal_convention : String
  certified_error_bound : Bool
} derive(ToJson)

///|
pub extend SurfaceNormalIntegral with ToJson::{to_json}

///|
/// Integrate scalar s times du x dv using the complete surface interpolation.
/// NodeData is scalar Lagrange data; ElementData is constant on each face.
/// Explicit frame/coverage/sample contracts match the existing surface APIs.
/// Pressure traction signs must be supplied by the caller, not inferred here.
pub fn Mesh::integrate_surface_normal_field(
  self : Mesh,
  field_index : Int,
  max_samples? : Int = 1000000,
) -> SurfaceNormalIntegral raise {
  let plan = self.surface_field_plan(field_index, max_samples)
  let f = plan.frame
  if f.integers[1] != 1 {
    bad("surface normal field integration requires exactly 1 scalar component")
  }
  let total_area = surface_sum()
  let total_vector = Array::makei(3, _ => surface_sum())
  let total_normal = Array::makei(3, _ => surface_sum())
  let mut zeros = 0
  for e in self.es {
    if element_shape(e.kind).0 != 2 {
      continue
    }
    let cell_area = surface_sum()
    let cell_vector = Array::makei(3, _ => surface_sum())
    let cell_normal = Array::makei(3, _ => surface_sum())
    for (p, weight) in surface_quadrature(e.kind == 2 || e.kind == 9) {
      let columns = self.surface_columns(e, p)
      let cross = scaled_cross_values(columns[0], columns[1])
      let measure = scaled_norm(cross)
      if measure.mantissa == 0.0 {
        zeros += 1
      }
      cell_area.add(measure.times(scaled(weight)))
      let weighted = cross.map(x => x.times(scaled(weight)))
      for k in 0..<3 {
        cell_vector[k].add(weighted[k])
      }
      if f.location == "NodeData" {
        let scalar = surface_nodal_value(
          e,
          surface_basis(e.kind, p),
          plan.data,
          0,
        )
        // Keep scalar and derivative cross product coupled at each point.
        // A face average times its area vector loses this correlation.
        for k in 0..<3 {
          cell_normal[k].add(scalar.times(weighted[k]))
        }
      }
    }
    total_area.add(cell_area.finish())
    for k in 0..<3 {
      let vector = cell_vector[k].finish()
      total_vector[k].add(vector)
      total_normal[k].add(
        if f.location == "NodeData" {
          cell_normal[k].finish()
        } else {
          vector.times(scaled(plan.data[e.tag][0]))
        },
      )
    }
  }
  {
    field_index,
    name: f.strings[0],
    location: f.location,
    time_step: f.integers[0],
    time: if f.reals.is_empty() {
      None
    } else {
      Some(f.reals[0])
    },
    elements: plan.elements,
    skipped_lower_dimension: self.es.length() - plan.elements,
    samples: plan.samples,
    rules: plan.rules,
    surface_measure: total_area.finish().value("normal field surface measure"),
    area_vector: total_vector.map(s => {
      s.finish().value("integrated oriented area")
    }),
    normal_integral: total_normal.map(s => {
      s.finish().value("surface scalar normal integral")
    }),
    zero_measure_samples: zeros,
    normal_convention: "stored_node_winding",
    certified_error_bound: false,
  }
}
