import gleam/int
import promgleam/metrics/counter
import promgleam/metrics/histogram
import promgleam/registry

const registry = "rpc"

const rpc_requests_counter = "rpc_requests_total"

const rpc_token_counter = "rpc_tokens_total"

const rpc_duration_histogram = "rpc_duration_seconds"

const rpc_byte_size_histogram = "rpc_byte_size"

pub fn setup() {
  let assert Ok(_) =
    counter.create_counter(
      registry,
      rpc_requests_counter,
      "Total number of RPC requests",
      ["method", "status"],
    )

  let assert Ok(_) =
    counter.create_counter(
      registry,
      rpc_token_counter,
      "Total number of ratelimit tokens consumed",
      ["method"],
    )

  let assert Ok(_) =
    histogram.create_histogram(
      registry,
      rpc_duration_histogram,
      "Duration of RPC requests in seconds",
      ["method"],
      [0.01, 0.02, 0.05, 0.1, 0.2, 0.5, 1.0],
    )

  let assert Ok(_) =
    histogram.create_histogram(
      registry,
      rpc_byte_size_histogram,
      "Size of RPC responses in bytes",
      ["method"],
      [
        100.0, 200.0, 500.0, 1000.0, 2000.0, 5000.0, 10_000.0, 20_000.0,
        50_000.0, 100_000.0,
      ],
    )

  Nil
}

pub fn count_rpc_request(
  method method: String,
  duration duration: Int,
  byte_size byte_size: Int,
  tokens tokens: Int,
  is_ok is_ok: Bool,
) {
  let assert Ok(_) =
    counter.increment_counter(
      registry,
      rpc_requests_counter,
      [
        method,
        case is_ok {
          True -> "ok"
          False -> "notok"
        },
      ],
      1,
    )

  let assert Ok(_) =
    counter.increment_counter(registry, rpc_token_counter, [method], tokens)

  let assert Ok(_) =
    histogram.observe_histogram(
      registry,
      rpc_duration_histogram,
      [method],
      { duration |> int.to_float() } *. 1_000_000.0,
    )

  let assert Ok(_) =
    histogram.observe_histogram(
      registry,
      rpc_byte_size_histogram,
      [method],
      byte_size |> int.to_float(),
    )

  Nil
}

pub fn print() {
  registry.print_as_text(registry)
}
