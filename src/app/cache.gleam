/// The cache module provides a store for ratelimits in memory.
/// The cache is implemented as an actor that can be interacted
/// with using messages.
///
/// The cache runs in a separate process rather than being passed around as a
/// value. This allows the cache to be shared between multiple processes
/// without having to worry about synchronization and copying.
///
import gleam/bool
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/io
import gleam/option
import gleam/otp/actor
import gleam/time/timestamp.{type Timestamp}

import app/ratelimit.{type Ratelimit}

const timeout = 3000

/// A simple type alias for a store of ratelimits.
type Store =
  Dict(String, Ratelimit)

/// A type alias for a Gleam subject used to interact
/// with the cache actor.
pub type Cache =
  Subject(Message)

/// Messages that can be sent to the cache actor.
pub type Message {
  Check(reply_with: Subject(#(Int, Timestamp)), ip: String)
  Consume(reply_with: Subject(Ratelimit), ip: String, tokens: Int)
  Vacuum
  Shutdown
}

/// Handle messages sent to the cache actor.
fn handle_message(message: Message, store: Store) -> actor.Next(Message, Store) {
  case message {
    Check(client, ip) -> {
      let bucket = store |> dict.get(ip) |> option.from_result()
      client |> process.send(ratelimit.remaining_tokens(bucket))
      actor.continue(store)
    }
    Consume(client, ip, tokens) -> {
      let bucket = store |> dict.get(ip) |> option.from_result()
      let bucket = bucket |> ratelimit.consume(tokens)
      process.send(client, bucket)
      actor.continue(store |> dict.insert(ip, bucket))
    }
    Vacuum -> {
      let before = store |> dict.size()
      let store =
        store
        |> dict.filter(fn(_ip, bucket) {
          bucket |> ratelimit.is_expired() |> bool.negate()
        })
      let after = store |> dict.size()
      let removed = before - after
      io.println(
        "VACUUM ratelimiter: removed "
        <> removed |> int.to_string()
        <> ", "
        <> after |> int.to_string()
        <> " remaining",
      )
      actor.continue(store)
    }
    Shutdown -> actor.Stop(process.Normal)
  }
}

/// Create a new cache.
pub fn new() -> Result(Subject(Message), actor.StartError) {
  actor.start(dict.new(), handle_message)
}

/// Check remaining tokens for the given IP.
pub fn check(cache: Cache, ip: String) -> #(Int, Timestamp) {
  actor.call(cache, Check(_, ip), timeout)
}

/// Consume tokens from an IP's ratelimit.
pub fn consume(cache: Cache, ip: String, tokens: Int) -> Ratelimit {
  actor.call(cache, Consume(_, ip, tokens), timeout)
}

/// Remove cache entries that have expired.
pub fn vacuum(cache: Cache) {
  process.send(cache, Vacuum)
}

/// Shutdown the cache.
pub fn shutdown(cache: Cache) {
  process.send(cache, Shutdown)
}
