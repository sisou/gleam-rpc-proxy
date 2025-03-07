import gleam/int
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/time/duration
import gleam/time/timestamp.{type Timestamp}

import app/config.{type RatelimitConfig}

pub type Ratelimit {
  Bucket(tokens: Int, reset: Timestamp)
}

pub fn new(opts: RatelimitConfig) -> Ratelimit {
  Bucket(
    tokens: opts.initial_tokens,
    reset: timestamp.system_time()
      |> timestamp.add(duration.seconds(opts.duration_seconds)),
  )
}

pub fn remaining_tokens(
  bucket: Option(Ratelimit),
  opts: RatelimitConfig,
) -> #(Int, Timestamp) {
  case bucket {
    Some(bucket) ->
      case bucket |> is_expired() {
        False -> #(bucket.tokens, bucket.reset)
        True -> #(opts.initial_tokens, timestamp.from_unix_seconds(0))
      }
    None -> #(opts.initial_tokens, timestamp.from_unix_seconds(0))
  }
}

/// Consumes tokens from a bucket. If the tokens are more than are remaining in the bucket, the bucket is set to 0.
/// There is no carry-over of tokens into a next bucket window.
pub fn consume(
  bucket: Option(Ratelimit),
  tokens: Int,
  opts: RatelimitConfig,
) -> Ratelimit {
  let new = fn() { new(opts) }
  let consume = fn(bucket, tokens) { consume(bucket, tokens, opts) }

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
