///|
pub fn StorePutResult::label(self : StorePutResult) -> String {
  match self {
    StoreInserted => "INSERTED"
    StoreReplacedResult => "REPLACED"
    StoreRejectedNoStore => "REJECTED_NO_STORE"
    StoreRejectedOversized => "REJECTED_OVERSIZED"
    StoreRejectedCapacity => "REJECTED_CAPACITY"
  }
}

///|
pub fn StorePutResult::accepted(self : StorePutResult) -> Bool {
  self is StoreInserted || self is StoreReplacedResult
}

///|
pub fn StoreStats::requests(self : StoreStats) -> Int64 {
  if self.hits >= MAX_DELTA_SECONDS - self.misses {
    MAX_DELTA_SECONDS
  } else {
    self.hits + self.misses
  }
}

///|
/// Integer hit ratio in thousandths, suitable for deterministic reports.
pub fn StoreStats::hit_rate_per_mille(self : StoreStats) -> Int {
  let requests = self.requests()
  if requests <= 0 {
    0
  } else if self.hits >= requests {
    1_000
  } else {
    (self.hits * 1_000 / requests).to_int()
  }
}

///|
pub fn StoreStats::saved_origin_requests(self : StoreStats) -> Int64 {
  self.hits
}

///|
pub fn StoreStats::is_empty(self : StoreStats) -> Bool {
  self.entries == 0 && self.body_bytes == 0
}

///|
fn stats_int64_json(value : Int64) -> Json {
  Json::number(value.to_double(), repr=value.to_string())
}

///|
pub fn StoreStats::to_json(self : StoreStats) -> Json {
  Json::object({
    "entries": self.entries,
    "body_bytes": stats_int64_json(self.body_bytes),
    "puts": stats_int64_json(self.puts),
    "replacements": stats_int64_json(self.replacements),
    "evictions": stats_int64_json(self.evictions),
    "lookups": stats_int64_json(self.lookups),
    "hits": stats_int64_json(self.hits),
    "misses": stats_int64_json(self.misses),
    "requests": stats_int64_json(self.requests()),
    "hit_rate_per_mille": self.hit_rate_per_mille(),
    "saved_origin_requests": stats_int64_json(self.saved_origin_requests()),
    "invalidated_entries": stats_int64_json(self.invalidated_entries),
    "rejected_entries": stats_int64_json(self.rejected_entries),
  })
}

///|
pub fn StoreStats::json_report(self : StoreStats) -> String {
  self.to_json().stringify(indent=2)
}

///|
pub fn StoreStats::text_report(self : StoreStats) -> String {
  [
    "Entries: \{self.entries}",
    "Body bytes: \{self.body_bytes}",
    "Puts: \{self.puts}",
    "Replacements: \{self.replacements}",
    "Evictions: \{self.evictions}",
    "Lookups: \{self.lookups}",
    "Hits: \{self.hits}",
    "Misses: \{self.misses}",
    "Hit rate: \{self.hit_rate_per_mille()}/1000",
    "Invalidated entries: \{self.invalidated_entries}",
    "Rejected entries: \{self.rejected_entries}",
  ].join("\n")
}
