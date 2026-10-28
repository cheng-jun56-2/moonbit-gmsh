///|
/// Signed vector throughput follows stored node winding. The area vector is
/// integral(n dA); surface_measure is the nonnegative area estimate. No
/// automatic outward correction, unit inference or global certificate occurs.
pub(all) struct SurfaceFlux {
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
  flux : Double
  zero_measure_samples : Int
  normal_convention : String
  certified_error_bound : Bool
} derive(ToJson)

///|
pub extend SurfaceFlux with ToJson::{to_json}

///|
/// One current surface element's contribution. input_index refers to the
/// zero-based Mesh::elements snapshot, including skipped lower dimensions.
/// Tags change after compact; neither identifier is an original parent ID.
pub(all) struct SurfaceFluxContribution {
  element : Int
  input_index : Int
  kind : Int
  entity : Int
  samples : Int
  surface_measure : Double
  area_vector : Array[Double]
  flux : Double
  zero_measure_samples : Int
} derive(ToJson)

///|
pub extend SurfaceFluxContribution with ToJson::{to_json}

///|
pub(all) struct SurfaceFluxBreakdown {
  total : SurfaceFlux
  contributions : Array[SurfaceFluxContribution]
} derive(ToJson)

///|
pub extend SurfaceFluxBreakdown with ToJson::{to_json}

///|
/// Integrate a supplied three-component Cartesian field dotted with du x dv.
/// NodeData uses the full element's standard Lagrange interpolation;
/// ElementData is constant per face. Select a precise frame and complete 2D
/// surface explicitly. Reversal of stored winding reverses flux; this is not
/// proof of geometric outwardness. Same Gauss4/CompositeGauss4 rules as field
/// integration, with no certified floating-point error bound.
pub fn Mesh::integrate_surface_flux(
  self : Mesh,
  field_index : Int,
  max_samples? : Int = 1000000,
) -> SurfaceFlux raise {
  let plan = self.surface_field_plan(field_index, max_samples)
  self.surface_flux_compute(field_index, plan, false).total
}

///|
/// Compute the same total plus bounded, ordered per-face contributions in one
/// geometry pass. Every row must be representable, even if its value would
/// cancel in the total. No truncation or automatic orientation repair occurs.
pub fn Mesh::surface_flux_breakdown(
  self : Mesh,
  field_index : Int,
  max_samples? : Int = 1000000,
  max_elements? : Int = 10000,
) -> SurfaceFluxBreakdown raise {
  if max_elements < 0 || max_elements > 100000 {
    bad("surface flux max_elements must be 0..100000")
  }
  let plan = self.surface_field_plan(field_index, max_samples)
  if plan.elements > max_elements {
    bad(
      "surface flux element budget exceeded; no partial contributions returned",
    )
  }
  self.surface_flux_compute(field_index, plan, true)
}

///|
fn Mesh::surface_flux_compute(
  self : Mesh,
  field_index : Int,
  plan : SurfaceFieldPlan,
  collect : Bool,
) -> SurfaceFluxBreakdown raise {
  let f = plan.frame
  if f.integers[1] != 3 {
    bad("surface normal flux requires exactly 3 vector components")
  }
  let total_area = surface_sum()
  let total_vector = Array::makei(3, _ => surface_sum())
  let total_flux = surface_sum()
  let contributions : Array[SurfaceFluxContribution] = []
  let mut zeros = 0
  for input_index, e in self.es {
    if element_shape(e.kind).0 != 2 {
      continue
    }
    let cell_area = surface_sum()
    let cell_vector = Array::makei(3, _ => surface_sum())
    let cell_flux = surface_sum()
    let rule = surface_quadrature(e.kind == 2 || e.kind == 9)
    let mut cell_zeros = 0
    for (p, weight) in rule {
      let columns = self.surface_columns(e, p)
      let cross = scaled_cross_values(columns[0], columns[1])
      let measure = scaled_norm(cross)
      if measure.mantissa == 0.0 {
        zeros += 1
        cell_zeros += 1
      }
      cell_area.add(measure.times(scaled(weight)))
      let weighted = cross.map(x => x.times(scaled(weight)))
      for k in 0..<3 {
        cell_vector[k].add(weighted[k])
      }
      if f.location == "NodeData" {
        let b = surface_basis(e.kind, p)
        let value = [
          for k in 0..<3 => surface_nodal_value(e, b, plan.data, k)
        ]
        // Form the dot product directly in the protected range. Normalizing
        // first can erase tiny components; component integrals can overflow
        // even when the normal flux itself is finite.
        cell_flux.add(scaled_dot_values(value, weighted))
      }
    }
    let area = cell_area.finish()
    let vector = cell_vector.map(s => s.finish())
    let flux = if f.location == "NodeData" {
      cell_flux.finish()
    } else {
      scaled_dot_values(plan.data[e.tag].map(scaled), vector)
    }
    total_area.add(area)
    for k in 0..<3 {
      total_vector[k].add(vector[k])
    }
    total_flux.add(flux)
    if collect {
      contributions.push({
        element: e.tag,
        input_index,
        kind: e.kind,
        entity: e.entity,
        samples: rule.length(),
        surface_measure: area.value("surface measure for element \{e.tag}"),
        area_vector: vector.map(v => {
          v.value("oriented area for element \{e.tag}")
        }),
        flux: flux.value("normal flux for element \{e.tag}"),
        zero_measure_samples: cell_zeros,
      })
    }
  }
  let total : SurfaceFlux = {
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
    surface_measure: total_area.finish().value("flux surface measure"),
    area_vector: total_vector.map(s => {
      s.finish().value("integrated oriented area")
    }),
    flux: total_flux.finish().value("surface normal flux"),
    zero_measure_samples: zeros,
    normal_convention: "stored_node_winding",
    certified_error_bound: false,
  }
  { total, contributions, }
}
