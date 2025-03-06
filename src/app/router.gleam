/// Routes defined in our application.
///
/// We use a single handler for all requests, and route the request
/// based on the path segments. This allows us to keep all of our
/// application logic in one place, and to easily add new routes.
///
import app/rpc_message.{type RpcRequest, RpcError, RpcRequest, RpcResult}
import gleam/dynamic/decode
import gleam/float
import gleam/http
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/pair
import gleam/result
import gleam/string
import gleam/time/duration
import gleam/time/timestamp.{type Timestamp}

import app/cache
import app/context.{type Context}
import app/rpc_api

import wisp.{type Request, type Response}

/// Route the request to the appropriate handler based on the path segments.
pub fn handle_request(req: Request, ctx: Context) -> Response {
  // use <- wisp.log_request(req)
  case wisp.path_segments(req), req.method {
    // Main handler
    [], http.Post -> proxy(req, ctx)
    [], http.Get -> landing_page()
    [], _ -> wisp.method_not_allowed(allowed: [http.Get, http.Post])
    // Health check
    ["health"], http.Get -> wisp.ok()
    // Any non-matching routes
    _, _ -> wisp.not_found()
  }
}

fn proxy(req: Request, ctx: Context) -> Response {
  use ip <- require_ip(req)
  use body <- wisp.require_string_body(req)

  // Decode request body and check method against allowlist
  use request <- decode_request_body(body)
  use <- check_ratelimit(ctx, ip, request)
  use <- check_method_allowlist(request)

  // Forward request
  let start_time = timestamp.system_time()
  case rpc_api.make_request(body, ctx.rpc_connection) {
    Ok(res) -> {
      let elapsed_time =
        start_time |> timestamp.difference(timestamp.system_time())
      // Decode response and make consumed tokens depend on the RPC result length
      let consumed_tokens = case
        json.parse(res, rpc_message.rpc_response_decoder())
      {
        Ok(RpcResult(result:, ..)) -> {
          let nimiq_data_decoder = {
            use data <- decode.field("data", decode.list(decode.dynamic))
            decode.success(data)
          }
          case decode.run(result, nimiq_data_decoder) {
            Ok(array) ->
              { array |> list.length() |> int.to_float() } /. 100.0
              |> float.ceiling()
              |> float.round()
            Error(_) -> 1
          }
        }
        Ok(RpcError(..)) -> {
          io.println_error("ERROR: RPC error response: " <> res)
          1
        }
        Error(_) -> {
          io.println_error("ERROR: Invalid RPC response: " <> res)
          1
        }
      }

      let limit = ctx.ratelimit_cache |> cache.consume(ip, consumed_tokens)

      io.println(
        "PROXY "
        <> request.method
        <> ": "
        <> {
          elapsed_time
          |> duration.to_seconds()
        }
        *. 1000.0
        |> float.round()
        |> int.to_string()
        <> "ms, "
        <> res |> string.byte_size() |> int.to_string()
        <> " B, "
        <> consumed_tokens |> int.to_string()
        <> " token"
        <> case consumed_tokens == 1 {
          True -> ""
          False -> "s"
        },
      )

      wisp.ok()
      |> wisp.string_body(res)
      |> add_ratelimit_headers(limit.tokens, limit.reset)
    }
    Error(err) -> wisp.internal_server_error() |> wisp.string_body(err)
  }
}

fn require_ip(req: Request, next: fn(String) -> Response) -> Response {
  let ip =
    req.headers
    |> list.find(fn(pair) { pair.0 == "x-forwarded-for" })
    |> result.map(fn(pair) {
      let assert Ok(ip) = pair.1 |> string.split(",") |> list.first()
      Some(ip)
    })
    |> result.unwrap(None)

  case ip {
    Some(ip) -> next(ip)
    None -> wisp.bad_request() |> wisp.string_body("Missing IP address")
  }
}

fn check_ratelimit(
  ctx: Context,
  ip: String,
  request: RpcRequest,
  next: fn() -> Response,
) -> Response {
  let #(remaining_tokens, reset) = cache.check(ctx.ratelimit_cache, ip)
  case remaining_tokens > 0 {
    True -> next()
    False ->
      wisp.response(429)
      |> wisp.string_body(rpc_message.encode_rpc_error(
        request.id,
        "Rate limit exceeded",
      ))
      |> add_ratelimit_headers(remaining_tokens, reset)
  }
}

fn decode_request_body(
  body: String,
  next: fn(RpcRequest) -> Response,
) -> Response {
  case json.parse(body, rpc_message.rpc_request_decoder()) {
    Ok(request) -> next(request)
    Error(_) ->
      wisp.bad_request() |> wisp.string_body("Invalid JSON-RPC request")
  }
}

const allowed_methods = ["getBlockNumber", "getTransactionHashesByAddress"]

fn check_method_allowlist(
  request: RpcRequest,
  next: fn() -> Response,
) -> Response {
  case allowed_methods |> list.contains(request.method) {
    True -> next()
    False ->
      wisp.bad_request()
      |> wisp.string_body(rpc_message.encode_rpc_error(
        request.id,
        "Method not allowed",
      ))
  }
}

fn landing_page() -> Response {
  // TODO: Add a landing page
  wisp.ok()
  |> wisp.string_body("Nimiq Albatross public RPC")
}

fn add_ratelimit_headers(
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
