///|
pub(all) struct AgeCalculation {
  apparent_age : DeltaSeconds
  response_delay : DeltaSeconds
  age_value : DeltaSeconds
  corrected_age_value : DeltaSeconds
  corrected_initial_age : DeltaSeconds
  resident_time : DeltaSeconds
  current_age : DeltaSeconds
  clock_clamped : Bool
  overflow_clamped : Bool
} derive(Eq, Debug)

///|
fn add_delta_with_overflow(
  left : DeltaSeconds,
  right : DeltaSeconds,
) -> (DeltaSeconds, Bool) {
  let overflow = left.seconds() > MAX_DELTA_SECONDS - right.seconds()
  (left.saturating_add(right), overflow)
}

///|
fn response_age_value(response : ResponseMeta) -> DeltaSeconds {
  match response.headers.get_first("age") {
    Some(value) => parse_delta_seconds(value).unwrap_or(DeltaSeconds::zero())
    None => DeltaSeconds::zero()
  }
}

///|
/// Calculate corrected current age according to RFC 9111 section 4.2.3.
pub fn calculate_current_age(
  response : ResponseMeta,
  now : Timestamp,
) -> AgeCalculation {
  let parsed_date = match response.headers.get_first("date") {
    Some(value) => parse_http_date(value)
    None => None
  }
  let date_value = parsed_date.unwrap_or(response.response_time)
  let apparent_age = response.response_time.elapsed_since(date_value)
  let response_delay = response.response_time.elapsed_since(
    response.request_time,
  )
  let age_value = response_age_value(response)
  let (corrected_age_value, first_overflow) = add_delta_with_overflow(
    age_value, response_delay,
  )
  let corrected_initial_age = apparent_age.max(corrected_age_value)
  let resident_time = now.elapsed_since(response.response_time)
  let (current_age, second_overflow) = add_delta_with_overflow(
    corrected_initial_age, resident_time,
  )
  AgeCalculation::{
    apparent_age,
    response_delay,
    age_value,
    corrected_age_value,
    corrected_initial_age,
    resident_time,
    current_age,
    clock_clamped: date_value.seconds() > response.response_time.seconds() ||
    response.request_time.seconds() > response.response_time.seconds() ||
    response.response_time.seconds() > now.seconds(),
    overflow_clamped: first_overflow || second_overflow,
  }
}
