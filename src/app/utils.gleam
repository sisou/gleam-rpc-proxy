import gleam/int
import gleam/pair
import gleam/time/timestamp.{type Timestamp}

import wisp.{type Response}

pub fn add_ratelimit_headers(
  res: Response,
  tokens: Int,
  reset: Timestamp,
) -> Response {
  res
  |> wisp.set_header("x-ratelimit-remaining", tokens |> int.to_string())
  |> wisp.set_header(
    "x-ratelimit-reset",
    reset
      |> timestamp.to_unix_seconds_and_nanoseconds()
      |> pair.first()
      |> int.to_string(),
  )
}
