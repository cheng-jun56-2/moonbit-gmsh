///|
/// Fixed-rule component integrals over the stored 2D cells. Values use the
/// field's units times squared coordinate units; no unit conversion is inferred.
pub(all) struct SurfaceIntegral {
  field_index : Int
  name : String
  location : String
  time_step : Int
  time : Double?
  components : Int
  elements : Int
  skipped_lower_dimension : Int
  samples : Int
  rules : Array[String]
  surface_measure : Double
  integral : Array[Double]
  zero_measure_samples : Int
  certified_error_bound : Bool
} derive(ToJson)

///|
pub extend SurfaceIntegral with ToJson::{to_json}

///|
priv struct SurfaceSum {
  mut sum : Scaled
  mut correction : Scaled
}

///|
fn surface_sum() -> SurfaceSum {
  { sum: scaled(0.0), correction: scaled(0.0), }
}

///|
/// Neumaier accumulation in the existing protected range. This reduces loss
/// when signed contributions cancel; it is not exact/adaptive arithmetic.
fn SurfaceSum::add(self : SurfaceSum, value : Scaled) -> Unit {
  let next = self.sum.plus(value)
  let lost = if scaled_positive_less(self.sum.absolute(), value.absolute()) {
    value.plus(next.negative()).plus(self.sum)
  } else {
    self.sum.plus(next.negative()).plus(value)
  }
  self.correction = self.correction.plus(lost)
  self.sum = next
}

///|
fn SurfaceSum::finish(self : SurfaceSum) -> Scaled {
  self.sum.plus(self.correction)
}

///|
/// Degree4 rules on the triangle and tensor-product quadrangle. Numeric
/// triangle constants are mathematical data checked against Gmsh4.15.2
/// getIntegrationPoints(Gauss4); no upstream implementation is used at runtime.
fn surface_quadrature(triangle : Bool) -> Array[(Array[Double], Double)] {
  if triangle {
    let a = 0.445948490915965
    let b = 0.108103018168070
    let c = 0.091576213509771
    let d = 0.816847572980459
    let w1 = 0.111690794839005
    let w2 = 0.054975871827661
    [
      ([a, a], w1),
      ([a, b], w1),
      ([b, a], w1),
      ([c, c], w2),
      ([c, d], w2),
      ([d, c], w2),
    ]
  } else {
    let q = (3.0 / 5.0).sqrt()
    let axis = [(-q, 5.0 / 9.0), (0.0, 8.0 / 9.0), (q, 5.0 / 9.0)]
    let out : Array[(Array[Double], Double)] = []
    for (u, wu) in axis {
      for (v, wv) in axis {
        out.push(([u, v], wu * wv))
      }
    }
    out
  }
}

///|
fn surface_basis(kind : Int, p : Array[Double]) -> Array[Jet] raise {
  let u : Jet = { v: p[0], d: [1.0, 0.0, 0.0], }
  let v : Jet = { v: p[1], d: [0.0, 1.0, 0.0], }
  if kind == 2 {
    [jadd(jconst(1.0), jscale(jadd(u, v), -1.0)), u, v]
  } else if kind == 3 {
    [
      for (a, b) in [(-1.0, -1.0), (1.0, -1.0), (1.0, 1.0), (-1.0, 1.0)] => {
        jscale(
          jmul(jadd(jconst(1.0), jscale(u, a)), jadd(jconst(1.0), jscale(v, b))),
          0.25,
        )
      }
    ]
  } else {
    basis(kind, p)
  }
}

///|
/// P1/Q1 corner maps are the same base subspaces already used by P2/Q2.
/// Keep derivatives as Scaled: a returned integral can be finite even when a
/// reference-coordinate derivative or an unweighted area cannot fit Double.
fn Mesh::surface_columns(
  self : Mesh,
  e : Element,
  p : Array[Double],
) -> Array[Array[Scaled]] raise {
  let base = if e.kind == 2 {
    { ..e, kind: 9, }
  } else if e.kind == 3 {
    { ..e, kind: 10, }
  } else {
    e
  }
  let mapped = self.corner_map(base, p)
  if e.kind != 2 && e.kind != 3 {
    let b = basis(e.kind, p)
    let residual = self.quadratic_remainders(e)
    for i in primary_count(e.kind)..<e.nodes.length() {
      for k in 0..<3 {
        mapped[k] = range_add(mapped[k], range_weighted(b[i], residual[i][k]))
      }
    }
  }
  [
    for j in 0..<2 => [ for k in 0..<3 => mapped[k].d[j] ]
  ]
}

///|
fn surface_nodal_value(
  e : Element,
  b : Array[Jet],
  data : Map[Int, Array[Double]],
  component : Int,
) -> Scaled {
  let terms = e.nodes.mapi((i, tag) => {
    scaled(data[tag][component]).times(scaled(b[i].v))
  })
  // Cancel comparable large terms before adding much smaller contributions.
  for i in 0..<terms.length() {
    for j in (i + 1)..<terms.length() {
      if terms[j].mantissa != 0.0 &&
        (terms[i].mantissa == 0.0 || terms[j].exponent > terms[i].exponent) {
        let old = terms[i]
        terms[i] = terms[j]
        terms[j] = old
      }
    }
  }
  let sum = surface_sum()
  for term in terms {
    sum.add(term)
  }
  sum.finish()
}

///|
priv struct SurfaceFieldPlan {
  frame : Field
  data : Map[Int, Array[Double]]
  elements : Int
  samples : Int
  rules : Array[String]
}

///|
/// Shared preflight keeps tag coverage, frame selection and budgets identical
/// for component integrals and oriented vector flux; it performs no geometry.
fn Mesh::surface_field_plan(
  self : Mesh,
  field_index : Int,
  max_samples : Int,
) -> SurfaceFieldPlan raise {
  if field_index < 0 || field_index >= self.fs.length() {
    bad("surface integration field_index is out of range")
  }
  if max_samples < 0 || max_samples > 9000000 {
    bad("surface integration max_samples must be 0..9000000")
  }
  let f = self.fs[field_index]
  if f.strings.length() > 1 && !f.strings[1].is_empty() {
    bad("surface integration does not implement named interpolation schemes")
  }
  let mut dimension = -1
  let mut elements = 0
  let mut samples = 0
  let mut triangles = false
  let mut quads = false
  for e in self.es {
    let d = element_shape(e.kind).0
    dimension = dimension.max(d)
    if d == 2 {
      if ![2, 3, 9, 10, 16].contains(e.kind) {
        bad("unsupported surface integration family")
      }
      let tri = e.kind == 2 || e.kind == 9
      elements += 1
      samples += if tri { 6 } else { 9 }
      triangles = triangles || tri
      quads = quads || !tri
    }
  }
  if dimension != 2 {
    bad(
      "surface integration requires a 2D mesh; explicitly extract/select the boundary first",
    )
  }
  if samples > max_samples {
    bad(
      "surface integration sample budget exceeded; no partial integral returned",
    )
  }
  let data : Map[Int, Array[Double]] = Map([])
  for entry in f.entries {
    data[entry.tag] = entry.values
  }
  for e in self.es {
    if element_shape(e.kind).0 != 2 {
      continue
    }
    let tags = if f.location == "NodeData" { e.nodes } else { [e.tag] }
    for tag in tags {
      if !data.contains(tag) {
        bad(
          "surface integration missing \{f.location} tag \{tag} for element \{e.tag}",
        )
      }
    }
  }
  let rules : Array[String] = []
  if triangles {
    rules.push("triangle:Gauss4")
  }
  if quads {
    rules.push("quadrangle:CompositeGauss4")
  }
  { frame: f, data, elements, samples, rules, }
}

///|
/// Select one exact zero-based field frame. Integrate NodeData with standard
/// nodal Lagrange interpolation or ElementData as cellwise constants, over
/// Tri3/Tri6/Quad4/Quad8/Quad9. Volumes must be explicitly reduced to a selected
/// boundary first. Every selected node/element needs data; missing values are
/// never replaced by zero. Vector/tensor components are integrated separately,
/// without an implicit normal projection. Fixed Gauss4/CompositeGauss4 results
/// have no certified error bound on general curved geometry.
pub fn Mesh::integrate_surface_field(
  self : Mesh,
  field_index : Int,
  max_samples? : Int = 1000000,
) -> SurfaceIntegral raise {
  let plan = self.surface_field_plan(field_index, max_samples)
  let f = plan.frame
  let data = plan.data
  let elements = plan.elements
  let samples = plan.samples
  let rules = plan.rules
  let components = f.integers[1]
  let total_area = surface_sum()
  let total = Array::makei(components, _ => surface_sum())
  let mut zeros = 0
  for e in self.es {
    if element_shape(e.kind).0 != 2 {
      continue
    }
    let cell_area = surface_sum()
    let cell = Array::makei(components, _ => surface_sum())
    for (p, weight) in surface_quadrature(e.kind == 2 || e.kind == 9) {
      let columns = self.surface_columns(e, p)
      let measure = scaled_norm(scaled_cross_values(columns[0], columns[1]))
      if measure.mantissa == 0.0 {
        zeros += 1
      }
      let weighted_area = measure.times(scaled(weight))
      cell_area.add(weighted_area)
      if f.location == "NodeData" {
        let b = surface_basis(e.kind, p)
        for k in 0..<components {
          cell[k].add(surface_nodal_value(e, b, data, k).times(weighted_area))
        }
      }
    }
    let area = cell_area.finish()
    total_area.add(area)
    for k in 0..<components {
      total[k].add(
        if f.location == "NodeData" {
          cell[k].finish()
        } else {
          area.times(scaled(data[e.tag][k]))
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
    components,
    elements,
    skipped_lower_dimension: self.es.length() - elements,
    samples,
    rules,
    surface_measure: total_area.finish().value("integrated surface measure"),
    integral: total.map(s => s.finish().value("surface field integral")),
    zero_measure_samples: zeros,
    certified_error_bound: false,
  }
}
