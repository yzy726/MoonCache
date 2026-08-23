///|
priv struct Flight[X] {
  key : String
  value : @async.Lazy[X]
  mut waiters : Int
  mut terminal_recorded : Bool
}

///|
pub(all) struct RequestGroupStats {
  started : Int64
  coalesced : Int64
  succeeded : Int64
  failed : Int64
  cancelled_waiters : Int64
  cancelled_flights : Int64
  active_flights : Int
  active_waiters : Int
  peak_active_flights : Int
} derive(Eq, Debug)

///|
pub(all) struct RequestGroupResult[X] {
  value : X
  coalesced : Bool
}

///|
/// Cancellation-safe singleflight coordinator.
///
/// The first caller for a key starts a lazy shared operation. Later callers
/// wait for the same immutable result or error. Cancelling one caller only
/// removes that waiter; when the final waiter is cancelled, the async runtime
/// cancels the shared operation automatically.
pub struct RequestGroup[X] {
  priv flights : Array[Flight[X]]
  priv clone_value : (X) -> X
  priv mut started : Int64
  priv mut coalesced : Int64
  priv mut succeeded : Int64
  priv mut failed : Int64
  priv mut cancelled_waiters : Int64
  priv mut cancelled_flights : Int64
  priv mut peak_active_flights : Int
}

///|
pub fn[X] RequestGroup::new(clone_value : (X) -> X) -> RequestGroup[X] {
  RequestGroup::{
    flights: [],
    clone_value,
    started: 0,
    coalesced: 0,
    succeeded: 0,
    failed: 0,
    cancelled_waiters: 0,
    cancelled_flights: 0,
    peak_active_flights: 0,
  }
}

///|
fn[X] RequestGroup::find_flight(
  self : RequestGroup[X],
  key : String,
) -> Flight[X]? {
  for flight in self.flights {
    if flight.key == key && !flight.terminal_recorded {
      return Some(flight)
    }
  }
  None
}

///|
fn[X] RequestGroup::remove_flight(self : RequestGroup[X], key : String) -> Unit {
  for index = self.flights.length() - 1; index >= 0; index = index - 1 {
    if self.flights[index].key == key {
      ignore(self.flights.remove(index))
      return
    }
  }
}

///|
fn[X] RequestGroup::record_terminal(
  self : RequestGroup[X],
  flight : Flight[X],
  succeeded : Bool,
) -> Unit {
  if flight.terminal_recorded {
    return
  }
  flight.terminal_recorded = true
  if succeeded {
    self.succeeded = self.succeeded + 1
  } else {
    self.failed = self.failed + 1
  }
  self.remove_flight(flight.key)
}

///|
fn[X] RequestGroup::release_waiter(
  self : RequestGroup[X],
  flight : Flight[X],
  cancelled : Bool,
) -> Unit {
  if flight.waiters > 0 {
    flight.waiters = flight.waiters - 1
  }
  if cancelled {
    self.cancelled_waiters = self.cancelled_waiters + 1
  }
  if cancelled && flight.waiters == 0 && !flight.terminal_recorded {
    flight.terminal_recorded = true
    self.cancelled_flights = self.cancelled_flights + 1
    self.remove_flight(flight.key)
  }
}

///|
async fn[X] RequestGroup::wait_for_flight(
  self : RequestGroup[X],
  flight : Flight[X],
  coalesced : Bool,
) -> RequestGroupResult[X] {
  let outcome : Result[X, Error] = Ok(flight.value.wait()) catch {
    error if @async.is_being_cancelled() => {
      self.release_waiter(flight, true)
      raise error
    }
    error => Err(error)
  }
  match outcome {
    Ok(value) => {
      self.record_terminal(flight, true)
      self.release_waiter(flight, false)
      RequestGroupResult::{ value: (self.clone_value)(value), coalesced }
    }
    Err(error) => {
      self.record_terminal(flight, false)
      self.release_waiter(flight, false)
      raise error
    }
  }
}

///|
/// Run or join the in-flight operation identified by `key`.
pub async fn[X] RequestGroup::run(
  self : RequestGroup[X],
  key : String,
  operation : async () -> X,
) -> RequestGroupResult[X] {
  match self.find_flight(key) {
    Some(flight) => {
      flight.waiters = flight.waiters + 1
      self.coalesced = self.coalesced + 1
      return self.wait_for_flight(flight, true)
    }
    None => ()
  }
  let flight = Flight::{
    key,
    value: @async.Lazy(operation),
    waiters: 1,
    terminal_recorded: false,
  }
  self.flights.push(flight)
  self.started = self.started + 1
  if self.flights.length() > self.peak_active_flights {
    self.peak_active_flights = self.flights.length()
  }
  self.wait_for_flight(flight, false)
}

///|
pub fn[X] RequestGroup::stats(self : RequestGroup[X]) -> RequestGroupStats {
  let mut active_waiters = 0
  for flight in self.flights {
    active_waiters = active_waiters + flight.waiters
  }
  RequestGroupStats::{
    started: self.started,
    coalesced: self.coalesced,
    succeeded: self.succeeded,
    failed: self.failed,
    cancelled_waiters: self.cancelled_waiters,
    cancelled_flights: self.cancelled_flights,
    active_flights: self.flights.length(),
    active_waiters,
    peak_active_flights: self.peak_active_flights,
  }
}
