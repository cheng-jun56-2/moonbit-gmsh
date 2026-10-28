///|
/// Reuse the existing mantissa/exponent representation for products and
/// norms. Range protection is not an exact/adaptive geometric predicate.
fn scaled_difference(a : Array[Double], b : Array[Double]) -> Array[Scaled] {
  [
    for i in 0..<3 => scaled(a[i]).plus(scaled(b[i]).negative())
  ]
}

///|
fn scaled_cross_values(a : Array[Scaled], b : Array[Scaled]) -> Array[Scaled] {
  [
    for i in 0..<3 => {
      let j = (i + 1) % 3
      let k = (i + 2) % 3
      a[j].times(b[k]).plus(a[k].times(b[j]).negative())
    }
  ]
}

///|
/// Differences and products can exceed Double even though the final unit
/// normal is representable. Never square an unscaled area vector.
fn scaled_triangle_cross(points : Array[Array[Double]]) -> Array[Scaled] {
  scaled_cross_values(
    scaled_difference(points[1], points[0]),
    scaled_difference(points[2], points[0]),
  )
}

///|
fn scaled_unit(vector : Array[Scaled]) -> Array[Double] {
  let length = scaled_norm(vector)
  if length.mantissa == 0.0 {
    return [0.0, 0.0, 0.0]
  }
  vector.map(x => {
    let q = x.divide(length)
    // A direction component smaller than the minimum subnormal rounds to0;
    // the absolute geometric measure is separately checked by Scaled::value.
    @math.scalbn(q.mantissa, q.exponent)
  })
}

///|
fn scaled_positive_less(a : Scaled, b : Scaled) -> Bool {
  if a.mantissa == 0.0 {
    b.mantissa != 0.0
  } else if b.mantissa == 0.0 {
    false
  } else if a.exponent == b.exponent {
    a.mantissa < b.mantissa
  } else {
    a.exponent < b.exponent
  }
}

///|
/// Both vectors may contain nonrepresentable intermediate coordinate
/// differences. As in scaled_dot, cancel comparable large terms first;
/// this protects range and is not an exact/adaptive orientation predicate.
fn scaled_dot_values(a : Array[Scaled], b : Array[Scaled]) -> Scaled {
  let terms = Array::makei(3, i => a[i].times(b[i]))
  for i in 0..<3 {
    for j in (i + 1)..<3 {
      if terms[j].mantissa != 0.0 &&
        (terms[i].mantissa == 0.0 || terms[j].exponent > terms[i].exponent) {
        let old = terms[i]
        terms[i] = terms[j]
        terms[j] = old
      }
    }
  }
  terms[0].plus(terms[1]).plus(terms[2])
}
