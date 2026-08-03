///|
/// The greatest non-negative duration accepted by MoonCache.
pub const MAX_DELTA_SECONDS : Int64 = 9_223_372_036_854_775_807

///|
/// A non-negative instant represented as caller-supplied epoch seconds.
pub struct Timestamp(Int64) derive(Eq, Compare, Debug, ToJson, FromJson)

///|
pub fn Timestamp::from_seconds(value : Int64) -> Timestamp {
  if value < 0 {
    Timestamp(0)
  } else {
    Timestamp(value)
  }
}

///|
pub fn Timestamp::zero() -> Timestamp {
  Timestamp(0)
}

///|
pub fn Timestamp::seconds(self : Timestamp) -> Int64 {
  self.0
}

///|
/// Return a non-negative duration even when the supplied clock moved backward.
pub fn Timestamp::elapsed_since(
  self : Timestamp,
  earlier : Timestamp,
) -> DeltaSeconds {
  if self.0 <= earlier.0 {
    DeltaSeconds(0)
  } else {
    DeltaSeconds(self.0 - earlier.0)
  }
}

///|
pub fn Timestamp::saturating_add(
  self : Timestamp,
  delta : DeltaSeconds,
) -> Timestamp {
  if self.0 >= MAX_DELTA_SECONDS - delta.0 {
    Timestamp(MAX_DELTA_SECONDS)
  } else {
    Timestamp(self.0 + delta.0)
  }
}

///|
/// A non-negative number of seconds. Construction and arithmetic saturate
/// instead of wrapping into negative values.
pub struct DeltaSeconds(Int64) derive(Eq, Compare, Debug, ToJson, FromJson)

///|
pub fn DeltaSeconds::from_seconds(value : Int64) -> DeltaSeconds {
  if value < 0 {
    DeltaSeconds(0)
  } else {
    DeltaSeconds(value)
  }
}

///|
pub fn DeltaSeconds::zero() -> DeltaSeconds {
  DeltaSeconds(0)
}

///|
pub fn DeltaSeconds::max_value() -> DeltaSeconds {
  DeltaSeconds(MAX_DELTA_SECONDS)
}

///|
pub fn DeltaSeconds::seconds(self : DeltaSeconds) -> Int64 {
  self.0
}

///|
pub fn DeltaSeconds::saturating_add(
  self : DeltaSeconds,
  other : DeltaSeconds,
) -> DeltaSeconds {
  if self.0 >= MAX_DELTA_SECONDS - other.0 {
    DeltaSeconds(MAX_DELTA_SECONDS)
  } else {
    DeltaSeconds(self.0 + other.0)
  }
}

///|
pub fn DeltaSeconds::saturating_sub(
  self : DeltaSeconds,
  other : DeltaSeconds,
) -> DeltaSeconds {
  if self.0 <= other.0 {
    DeltaSeconds(0)
  } else {
    DeltaSeconds(self.0 - other.0)
  }
}

///|
/// Scale a duration with integer arithmetic. Invalid or non-positive factors
/// produce zero; multiplication is rearranged to avoid overflow.
pub fn DeltaSeconds::saturating_scale(
  self : DeltaSeconds,
  numerator : Int64,
  denominator : Int64,
) -> DeltaSeconds {
  if self.0 == 0 || numerator <= 0 || denominator <= 0 {
    return DeltaSeconds(0)
  }
  let whole = self.0 / denominator
  let remainder = self.0 % denominator
  if whole > MAX_DELTA_SECONDS / numerator {
    return DeltaSeconds(MAX_DELTA_SECONDS)
  }
  let base = whole * numerator
  if remainder > MAX_DELTA_SECONDS / numerator {
    return DeltaSeconds(MAX_DELTA_SECONDS)
  }
  let fraction = remainder * numerator / denominator
  DeltaSeconds(base).saturating_add(DeltaSeconds(fraction))
}

///|
pub fn DeltaSeconds::min(
  self : DeltaSeconds,
  other : DeltaSeconds,
) -> DeltaSeconds {
  if self.0 <= other.0 {
    self
  } else {
    other
  }
}

///|
pub fn DeltaSeconds::max(
  self : DeltaSeconds,
  other : DeltaSeconds,
) -> DeltaSeconds {
  if self.0 >= other.0 {
    self
  } else {
    other
  }
}
