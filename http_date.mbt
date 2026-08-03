///|
fn parse_decimal_int(value : String) -> Int? {
  if value == "" {
    return None
  }
  for ch in value {
    if ch < '0' || ch > '9' {
      return None
    }
  }
  let parsed : Int? = Some(@strconv.from_str(value)) catch { _ => None }
  parsed
}

///|
fn month_number(value : String) -> Int? {
  match value {
    "Jan" => Some(1)
    "Feb" => Some(2)
    "Mar" => Some(3)
    "Apr" => Some(4)
    "May" => Some(5)
    "Jun" => Some(6)
    "Jul" => Some(7)
    "Aug" => Some(8)
    "Sep" => Some(9)
    "Oct" => Some(10)
    "Nov" => Some(11)
    "Dec" => Some(12)
    _ => None
  }
}

///|
fn is_leap_year(year : Int) -> Bool {
  year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
}

///|
fn days_in_month(year : Int, month : Int) -> Int {
  match month {
    1 | 3 | 5 | 7 | 8 | 10 | 12 => 31
    4 | 6 | 9 | 11 => 30
    2 => if is_leap_year(year) { 29 } else { 28 }
    _ => 0
  }
}

///|
fn leap_days_before_year(year : Int) -> Int64 {
  let previous = (year - 1).to_int64()
  previous / 4 - previous / 100 + previous / 400
}

///|
fn days_before_month(year : Int, month : Int) -> Int {
  let regular = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334]
  let base = regular[month - 1]
  if month > 2 && is_leap_year(year) {
    base + 1
  } else {
    base
  }
}

///|
fn civil_time_to_timestamp(
  year : Int,
  month : Int,
  day : Int,
  hour : Int,
  minute : Int,
  second : Int,
) -> Timestamp? {
  if year < 1970 ||
    year > 9999 ||
    month < 1 ||
    month > 12 ||
    day < 1 ||
    day > days_in_month(year, month) ||
    hour < 0 ||
    hour > 23 ||
    minute < 0 ||
    minute > 59 ||
    second < 0 ||
    second > 60 {
    return None
  }
  let years = (year - 1970).to_int64()
  let leap_days = leap_days_before_year(year) - leap_days_before_year(1970)
  let days = years * 365 +
    leap_days +
    days_before_month(year, month).to_int64() +
    (day - 1).to_int64()
  let seconds = days * 86_400 +
    hour.to_int64() * 3_600 +
    minute.to_int64() * 60 +
    second.to_int64()
  Some(Timestamp::from_seconds(seconds))
}

///|
fn http_date_separators_valid(value : String) -> Bool {
  value.code_unit_at(3) == ',' &&
  value.code_unit_at(4) == ' ' &&
  value.code_unit_at(7) == ' ' &&
  value.code_unit_at(11) == ' ' &&
  value.code_unit_at(16) == ' ' &&
  value.code_unit_at(19) == ':' &&
  value.code_unit_at(22) == ':' &&
  value.code_unit_at(25) == ' '
}

///|
fn valid_weekday(value : String) -> Bool {
  match value {
    "Mon" | "Tue" | "Wed" | "Thu" | "Fri" | "Sat" | "Sun" => true
    _ => false
  }
}

///|
/// Parse the IMF-fixdate form emitted by modern HTTP senders:
/// `Sun, 06 Nov 1994 08:49:37 GMT`.
///
/// Obsolete HTTP-date forms belong in optional protocol adapters; the cache
/// core intentionally implements only this narrow interoperable representation.
pub fn parse_http_date(value : String) -> Timestamp? {
  let text = value.trim(chars=" \t").to_owned()
  if text.length() != 29 || !http_date_separators_valid(text) {
    return None
  }
  if !valid_weekday(text.sub(start=0, end=3).to_owned()) {
    return None
  }
  if text.sub(start=26, end=29).to_owned() != "GMT" {
    return None
  }
  let day = parse_decimal_int(text.sub(start=5, end=7).to_owned())
  let month = month_number(text.sub(start=8, end=11).to_owned())
  let year = parse_decimal_int(text.sub(start=12, end=16).to_owned())
  let hour = parse_decimal_int(text.sub(start=17, end=19).to_owned())
  let minute = parse_decimal_int(text.sub(start=20, end=22).to_owned())
  let second = parse_decimal_int(text.sub(start=23, end=25).to_owned())
  match (year, month, day, hour, minute, second) {
    (Some(y), Some(m), Some(d), Some(h), Some(min), Some(sec)) =>
      civil_time_to_timestamp(y, m, d, h, min, sec)
    _ => None
  }
}
