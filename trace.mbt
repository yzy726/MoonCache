///|
pub(all) enum CacheActionKind {
  ServeFresh
  Revalidate
  Fetch
  ServeStale
  Bypass
  OnlyIfCachedMiss
} derive(Eq, Compare, Debug)

///|
pub fn CacheActionKind::label(self : CacheActionKind) -> String {
  match self {
    ServeFresh => "SERVE_FRESH"
    Revalidate => "REVALIDATE"
    Fetch => "FETCH"
    ServeStale => "SERVE_STALE"
    Bypass => "BYPASS"
    OnlyIfCachedMiss => "ONLY_IF_CACHED_MISS"
  }
}

///|
pub(all) struct CacheTrace {
  mut action : CacheActionKind
  reasons : Array[CacheReason]
  mut age : AgeCalculation?
  mut freshness_lifetime : DeltaSeconds?
  mut stale_by : DeltaSeconds?
  mut primary_key : String?
  mut selected_variant : String?
  mut validator : String?
  generated_headers : HeaderMap
} derive(Eq, Debug)

///|
pub fn CacheTrace::new(action : CacheActionKind) -> CacheTrace {
  CacheTrace::{
    action,
    reasons: [],
    age: None,
    freshness_lifetime: None,
    stale_by: None,
    primary_key: None,
    selected_variant: None,
    validator: None,
    generated_headers: HeaderMap::new(),
  }
}

///|
pub fn CacheTrace::add_reason(self : CacheTrace, reason : CacheReason) -> Unit {
  self.reasons.push(reason)
}

///|
pub fn CacheTrace::has_reason(
  self : CacheTrace,
  code : CacheReasonCode,
) -> Bool {
  self.reasons.any(fn(reason) { reason.code == code })
}

///|
fn delta_to_json(delta : DeltaSeconds) -> Json {
  Json::number(delta.seconds().to_double(), repr=delta.seconds().to_string())
}

///|
fn reason_to_json(reason : CacheReason) -> Json {
  let object : Map[String, Json] = {
    "code": reason.code.code(),
    "message": reason.code.message(),
  }
  match reason.detail {
    Some(detail) => object["detail"] = Json::string(detail)
    None => ()
  }
  match reason.rfc {
    Some(rfc) => object["rfc"] = Json::string(rfc)
    None => ()
  }
  Json::object(object)
}

///|
pub fn CacheTrace::to_json(self : CacheTrace) -> Json {
  let object : Map[String, Json] = {
    "action": self.action.label(),
    "reasons": Json::array(self.reasons.map(reason_to_json)),
  }
  match self.age {
    Some(age) => {
      object["apparent_age"] = delta_to_json(age.apparent_age)
      object["response_delay"] = delta_to_json(age.response_delay)
      object["corrected_initial_age"] = delta_to_json(age.corrected_initial_age)
      object["resident_time"] = delta_to_json(age.resident_time)
      object["current_age"] = delta_to_json(age.current_age)
      object["clock_clamped"] = Json::boolean(age.clock_clamped)
      object["overflow_clamped"] = Json::boolean(age.overflow_clamped)
    }
    None => ()
  }
  match self.freshness_lifetime {
    Some(lifetime) => object["freshness_lifetime"] = delta_to_json(lifetime)
    None => ()
  }
  match self.stale_by {
    Some(stale) => object["stale_by"] = delta_to_json(stale)
    None => ()
  }
  match self.primary_key {
    Some(key) => object["primary_key"] = Json::string(key)
    None => ()
  }
  match self.selected_variant {
    Some(variant) => object["selected_variant"] = Json::string(variant)
    None => ()
  }
  match self.validator {
    Some(validator) => object["validator"] = Json::string(validator)
    None => ()
  }
  if !self.generated_headers.is_empty() {
    let headers : Map[String, Json] = Map([])
    for pair in self.generated_headers.redacted().pairs() {
      headers[pair.0] = Json::string(pair.1)
    }
    object["generated_headers"] = Json::object(headers)
  }
  Json::object(object)
}

///|
pub fn CacheTrace::json_report(self : CacheTrace) -> String {
  self.to_json().stringify(indent=2)
}

///|
pub fn CacheTrace::text_report(self : CacheTrace) -> String {
  let lines : Array[String] = ["Decision: \{self.action.label()}"]
  match self.primary_key {
    Some(key) => lines.push("Primary key: \{key}")
    None => ()
  }
  match self.selected_variant {
    Some(variant) => lines.push("Variant: \{variant}")
    None => ()
  }
  match self.age {
    Some(age) => {
      lines.push("Apparent age: \{age.apparent_age.seconds()}s")
      lines.push("Response delay: \{age.response_delay.seconds()}s")
      lines.push(
        "Corrected initial age: \{age.corrected_initial_age.seconds()}s",
      )
      lines.push("Resident time: \{age.resident_time.seconds()}s")
      lines.push("Current age: \{age.current_age.seconds()}s")
    }
    None => ()
  }
  match self.freshness_lifetime {
    Some(lifetime) => lines.push("Freshness lifetime: \{lifetime.seconds()}s")
    None => ()
  }
  match self.stale_by {
    Some(stale) => lines.push("Stale by: \{stale.seconds()}s")
    None => ()
  }
  match self.validator {
    Some(validator) => lines.push("Validator: \{validator}")
    None => ()
  }
  for pair in self.generated_headers.redacted().pairs() {
    lines.push("Generated header: \{pair.0}: \{pair.1}")
  }
  for reason in self.reasons {
    let suffix = match reason.rfc {
      Some(rfc) => " [\{rfc}]"
      None => ""
    }
    lines.push(
      "Reason \{reason.code.code()}: \{reason.code.message()}\{suffix}",
    )
  }
  lines.join("\n")
}
