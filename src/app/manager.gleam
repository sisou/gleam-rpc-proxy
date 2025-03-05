/// The manager is a background process that runs periodic tasks.
///
/// It's designed as an OTP task that runs indefinitely.
///
import gleam/erlang/process
import gleam/otp/task

import app/cache.{type Cache}

// One minute
const sleep_milliseconds = 60_000

/// Start the manager. Creates a new task that will run indefinitely.
pub fn start(ratelimit_cache: Cache) {
  task.async(fn() { run(ratelimit_cache) })
}

/// Vacuum the ratelimit cache periodically.
///
/// Tail calls are optimised automatically in Gleam, so we don't need to worry
/// about stack overflows.
fn run(ratelimit_cache: Cache) {
  ratelimit_cache |> cache.vacuum()

  // Recursively call itself at an interval
  process.sleep(sleep_milliseconds)
  run(ratelimit_cache)
}
