///|
suberror RequestGroupTestError {
  RequestGroupTestError(String)
} derive(Eq, Debug)

///|
async test "request group coalesces twenty equal operations" {
  let group = RequestGroup::new(fn(value : Int) { value })
  let calls = [0]
  let results : Array[Int] = []
  @async.with_task_group() <| tasks => {
    for _ in 0..<20 {
      tasks.spawn_bg() <| () => {
        let result = group.run("same", () => {
          calls[0] = calls[0] + 1
          @async.sleep(20)
          42
        })
        results.push(result.value)
      }
    }
  }
  assert_eq(calls[0], 1)
  assert_eq(results.length(), 20)
  assert_true(results.all(fn(value) { value == 42 }))
  let stats = group.stats()
  assert_eq(stats.started, 1)
  assert_eq(stats.coalesced, 19)
  assert_eq(stats.succeeded, 1)
  assert_eq(stats.active_flights, 0)
  assert_eq(stats.active_waiters, 0)
}

///|
async test "request group keeps different keys independent" {
  let group = RequestGroup::new(fn(value : String) { value })
  let calls = [0]
  let results : Array[String] = []
  @async.with_task_group() <| tasks => {
    for key in ["en", "zh"] {
      tasks.spawn_bg() <| () => {
        let result = group.run(key, () => {
          calls[0] = calls[0] + 1
          @async.sleep(10)
          key
        })
        results.push(result.value)
      }
    }
  }
  assert_eq(calls[0], 2)
  results.sort()
  assert_eq(results, ["en", "zh"])
  assert_eq(group.stats().peak_active_flights, 2)
}

///|
async test "request group broadcasts one failure and removes its state" {
  let group = RequestGroup::new(fn(value : Int) { value })
  let calls = [0]
  let failures = [0]
  @async.with_task_group() <| tasks => {
    for _ in 0..<8 {
      tasks.spawn_bg(allow_failure=true) <| () => {
        try
          group.run("failure", () => {
            calls[0] = calls[0] + 1
            @async.sleep(20)
            raise RequestGroupTestError("origin failed")
          })
          |> ignore
        catch {
          RequestGroupTestError("origin failed") =>
            failures[0] = failures[0] + 1
          error => raise error
        }
      }
    }
  }
  assert_eq(calls[0], 1)
  assert_eq(failures[0], 8)
  assert_eq(group.stats().failed, 1)
  assert_eq(group.stats().active_flights, 0)
  let retry = group.run("failure", fn() { 7 })
  assert_eq(retry.value, 7)
  assert_eq(group.stats().started, 2)
}

///|
async test "cancelling a follower leaves the shared operation running" {
  let group = RequestGroup::new(fn(value : Int) { value })
  let calls = [0]
  let leader_result = [0]
  let follower_cancelled = [false]
  @async.with_task_group() <| tasks => {
    tasks.spawn_bg() <| () => {
      leader_result[0] = group.run("cancel-follower", () => {
          calls[0] = calls[0] + 1
          @async.sleep(40)
          9
        }).value
    }
    @async.sleep(2)
    let follower = tasks.spawn(allow_failure=true) <| () => {
      try group.run("cancel-follower", fn() { 99 }) |> ignore catch {
        error if @async.is_cancellation_error(error) => {
          follower_cancelled[0] = true
          raise error
        }
        error => raise error
      }
    }
    @async.sleep(2)
    follower.cancel()
  }
  assert_eq(calls[0], 1)
  assert_eq(leader_result[0], 9)
  assert_true(follower_cancelled[0])
  assert_eq(group.stats().cancelled_waiters, 1)
  assert_eq(group.stats().active_flights, 0)
}

///|
async test "cancelling the leader does not cancel an existing follower" {
  let group = RequestGroup::new(fn(value : Int) { value })
  let calls = [0]
  let leader_cancelled = [false]
  let follower_result = [0]
  @async.with_task_group() <| tasks => {
    let leader = tasks.spawn(allow_failure=true) <| () => {
      try
        group.run("cancel-leader", () => {
          calls[0] = calls[0] + 1
          @async.sleep(40)
          11
        })
        |> ignore
      catch {
        error if @async.is_cancellation_error(error) => {
          leader_cancelled[0] = true
          raise error
        }
        error => raise error
      }
    }
    @async.sleep(2)
    tasks.spawn_bg() <| () => {
      follower_result[0] = group.run("cancel-leader", fn() { 99 }).value
    }
    @async.sleep(2)
    leader.cancel()
  }
  assert_eq(calls[0], 1)
  assert_true(leader_cancelled[0])
  assert_eq(follower_result[0], 11)
  assert_eq(group.stats().active_flights, 0)
}

///|
async test "the last cancelled caller terminates the shared operation" {
  let group = RequestGroup::new(fn(value : Int) { value })
  let operation_cancelled = [false]
  let callers_cancelled = [0]
  @async.with_timeout(200, () => {
    @async.with_task_group() <| tasks => {
      let leader = tasks.spawn(allow_failure=true) <| () => {
        try
          group.run("cancel-all", () => {
            @async.sleep(1_000) catch {
              error if @async.is_cancellation_error(error) => {
                operation_cancelled[0] = true
                raise error
              }
              error => raise error
            }
            1
          })
          |> ignore
        catch {
          error if @async.is_cancellation_error(error) => {
            callers_cancelled[0] = callers_cancelled[0] + 1
            raise error
          }
          error => raise error
        }
      }
      @async.sleep(2)
      let follower = tasks.spawn(allow_failure=true) <| () => {
        try group.run("cancel-all", fn() { 2 }) |> ignore catch {
          error if @async.is_cancellation_error(error) => {
            callers_cancelled[0] = callers_cancelled[0] + 1
            raise error
          }
          error => raise error
        }
      }
      @async.sleep(2)
      leader.cancel()
      @async.sleep(2)
      follower.cancel()
    }
  })
  assert_true(operation_cancelled[0])
  assert_eq(callers_cancelled[0], 2)
  assert_eq(group.stats().cancelled_waiters, 2)
  assert_eq(group.stats().active_flights, 0)
  assert_eq(group.stats().active_waiters, 0)
}
