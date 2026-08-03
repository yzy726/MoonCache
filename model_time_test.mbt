///|
test "negative timestamps clamp to zero" {
  assert_eq(@MoonCache.Timestamp::from_seconds(-10).seconds(), 0)
}

///|
test "negative deltas clamp to zero" {
  assert_eq(@MoonCache.DeltaSeconds::from_seconds(-10).seconds(), 0)
}

///|
test "elapsed time is non-negative when clock moves backward" {
  let earlier = @MoonCache.Timestamp::from_seconds(20)
  let later = @MoonCache.Timestamp::from_seconds(10)
  assert_eq(later.elapsed_since(earlier).seconds(), 0)
}

///|
test "elapsed time uses injected seconds" {
  let earlier = @MoonCache.Timestamp::from_seconds(20)
  let later = @MoonCache.Timestamp::from_seconds(65)
  assert_eq(later.elapsed_since(earlier).seconds(), 45)
}

///|
test "delta addition saturates" {
  let max = @MoonCache.DeltaSeconds::max_value()
  let one = @MoonCache.DeltaSeconds::from_seconds(1)
  assert_eq(max.saturating_add(one), max)
}

///|
test "timestamp addition saturates" {
  let timestamp = @MoonCache.Timestamp::from_seconds(
    @MoonCache.MAX_DELTA_SECONDS,
  )
  assert_eq(
    timestamp.saturating_add(@MoonCache.DeltaSeconds::from_seconds(1)).seconds(),
    @MoonCache.MAX_DELTA_SECONDS,
  )
}

///|
test "delta subtraction clamps at zero" {
  let five = @MoonCache.DeltaSeconds::from_seconds(5)
  let ten = @MoonCache.DeltaSeconds::from_seconds(10)
  assert_eq(five.saturating_sub(ten).seconds(), 0)
  assert_eq(ten.saturating_sub(five).seconds(), 5)
}

///|
test "delta scale computes fractional lifetime" {
  let age = @MoonCache.DeltaSeconds::from_seconds(1_000)
  assert_eq(age.saturating_scale(1, 10).seconds(), 100)
}

///|
test "delta scale rejects invalid factors" {
  let age = @MoonCache.DeltaSeconds::from_seconds(1_000)
  assert_eq(age.saturating_scale(1, 0).seconds(), 0)
  assert_eq(age.saturating_scale(-1, 10).seconds(), 0)
}
