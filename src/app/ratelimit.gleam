import gleam/int
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/time/duration
import gleam/time/timestamp.{type Timestamp}

// Buckets contain 20 tokens and reset every 10 seconds
const initial_tokens = 20

const duration_seconds = 10

pub type Ratelimit {
  Bucket(tokens: Int, reset: Timestamp)
}

pub fn new() -> Ratelimit {
  Bucket(
    tokens: initial_tokens,
    reset: timestamp.system_time()
      |> timestamp.add(duration.seconds(duration_seconds)),
  )
}

pub fn remaining_tokens(bucket: Option(Ratelimit)) -> #(Int, Timestamp) {
  case bucket {
    Some(bucket) ->
      case bucket |> is_expired() {
        False -> #(bucket.tokens, bucket.reset)
        True -> #(initial_tokens, timestamp.from_unix_seconds(0))
      }
    None -> #(initial_tokens, timestamp.from_unix_seconds(0))
  }
}

/// Consumes tokens from a bucket. If the tokens are more than are remaining in the bucket, the bucket is set to 0.
/// There is no carry-over of tokens into a next bucket window.
pub fn consume(bucket: Option(Ratelimit), tokens: Int) -> Ratelimit {
  case bucket {
    Some(bucket) ->
      case bucket |> is_expired() {
        False ->
          Bucket(
            tokens: bucket.tokens - tokens |> int.max(0),
            reset: bucket.reset,
          )
        True -> Some(new()) |> consume(tokens)
      }
    None -> Some(new()) |> consume(tokens)
  }
}

pub fn is_expired(bucket: Ratelimit) -> Bool {
  case timestamp.system_time() |> timestamp.compare(bucket.reset) {
    order.Lt -> False
    _ -> True
  }
}
