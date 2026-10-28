///|
/// A signed mantissa and an unrestricted base-two exponent. Products stay
/// within Double mantissa range even when an intermediate area/volume does not.
/// This is range protection, not an exact/adaptive orientation predicate.
priv struct Scaled {
  mantissa : Double
  exponent : Int
}

///|
fn scaled(x : Double) -> Scaled {
  if x == 0.0 {
    return { mantissa: 0.0, exponent: 0, }
  }
  // Normalize subnormals first; scaling by 2^54 is exact.
  let raw = x.reinterpret_as_uint64()
  let subnormal = ((raw >> 52) & 2047UL) == 0UL
  let y = if subnormal { @math.scalbn(x, 54) } else { x }
  let bits = y.reinterpret_as_uint64()
  let exponent = ((bits >> 52) & 2047UL).to_int() -
    1023 -
    (if subnormal { 54 } else { 0 })
  let mantissa = ((bits & 0x800fffffffffffffUL) | 0x3ff0000000000000UL).reinterpret_as_double()
  { mantissa, exponent, }
}

///|
fn Scaled::times(a : Scaled, b : Scaled) -> Scaled {
  if a.mantissa == 0.0 || b.mantissa == 0.0 {
    return scaled(0.0)
  }
  let n = scaled(a.mantissa * b.mantissa)
  { mantissa: n.mantissa, exponent: n.exponent + a.exponent + b.exponent, }
}

///|
fn Scaled::divide(a : Scaled, b : Scaled) -> Scaled {
  let n = scaled(a.mantissa / b.mantissa)
  { mantissa: n.mantissa, exponent: n.exponent + a.exponent - b.exponent, }
}

///|
fn Scaled::plus(a : Scaled, b : Scaled) -> Scaled {
  if a.mantissa == 0.0 {
    return b
  }
  if b.mantissa == 0.0 {
    return a
  }
  let e = if a.exponent > b.exponent { a.exponent } else { b.exponent }
  let n = scaled(
    @math.scalbn(a.mantissa, a.exponent - e) +
    @math.scalbn(b.mantissa, b.exponent - e),
  )
  { mantissa: n.mantissa, exponent: n.exponent + e, }
}

///|
fn Scaled::negative(a : Scaled) -> Scaled {
  { ..a, mantissa: -a.mantissa, }
}

///|
fn Scaled::absolute(a : Scaled) -> Scaled {
  { ..a, mantissa: a.mantissa.abs(), }
}

///|
fn Scaled::value(a : Scaled, label : String) -> Double raise {
  let x = @math.scalbn(a.mantissa, a.exponent)
  if !finite(x) || (x == 0.0 && a.mantissa != 0.0) {
    bad("\{label} outside representable Double range")
  }
  x
}

///|
fn scaled_cross(a : Array[Double], b : Array[Double]) -> Array[Scaled] {
  let out = []
  for i in 0..<3 {
    let j = (i + 1) % 3
    let k = (i + 2) % 3
    out.push(
      scaled(a[j])
      .times(scaled(b[k]))
      .plus(scaled(a[k]).times(scaled(b[j])).negative()),
    )
  }
  out
}

///|
fn scaled_norm(a : Array[Scaled]) -> Scaled {
  let mut exponent = -10000
  for x in a {
    if x.mantissa != 0.0 && x.exponent > exponent {
      exponent = x.exponent
    }
  }
  if exponent == -10000 {
    return scaled(0.0)
  }
  let mut square = 0.0
  for x in a {
    let y = if x.mantissa == 0.0 {
      0.0
    } else {
      @math.scalbn(x.mantissa, x.exponent - exponent)
    }
    square = square + y * y
  }
  let n = scaled(square.sqrt())
  { mantissa: n.mantissa, exponent: n.exponent + exponent, }
}

///|
fn scaled_dot(a : Array[Scaled], b : Array[Double]) -> Scaled {
  let terms = Array::makei(3, i => a[i].times(scaled(b[i])))
  // Cancel comparable large terms before adding smaller ones. This protects
  // range but cannot recover bits already lost in nearly parallel input vectors.
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

///|
/// For positive x, split exponent into 3q+r before x^(2/3), keeping the
/// argument to pow in [1,8). Negative modulo is normalized explicitly.
fn Scaled::two_thirds(a : Scaled) -> Scaled {
  if a.mantissa == 0.0 {
    return a
  }
  let rem = (a.exponent % 3 + 3) % 3
  let n = scaled(@math.pow(@math.scalbn(a.mantissa, rem), 2.0 / 3.0))
  { mantissa: n.mantissa, exponent: n.exponent + 2 * ((a.exponent - rem) / 3), }
}
