/// Routes defined in our application.
///
/// We use a single handler for all requests, and route the request
/// based on the path segments. This allows us to keep all of our
/// application logic in one place, and to easily add new routes.
///
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode.{type Decoder}
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

import app/cache.{type Cache}
import app/config.{type RpcConfig, type ServerConfig, AllMethods, SomeMethods}
import app/context.{type Context}
import app/rpc_api
import app/rpc_message.{type RpcRequest, RpcError, RpcRequest, RpcResult}
import app/storage

import wisp.{type Request, type Response}

/// Route the request to the appropriate handler based on the path segments.
pub fn handle_request(req: Request, ctx: Context) -> Response {
  // use <- wisp.log_request(req)
  case wisp.path_segments(req), req.method {
    // Main handler
    [], http.Post -> proxy(req, ctx)
    [], http.Get -> landing_page(ctx.server_config)
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

  // Decode request body and check ratelimit and method allowlist
  use request <- decode_request_body(body)
  use <- check_ratelimit(ctx.ratelimit_cache, ip, request)
  use <- check_method_allowlist(request, ctx.rpc_config)

  // Forward request
  let start_time = timestamp.system_time()
  case rpc_api.make_request(body, ctx.rpc_config) {
    Ok(res) -> {
      let elapsed_time =
        start_time |> timestamp.difference(timestamp.system_time())
      // Decode response and make consumed tokens depend on the RPC result length
      let #(consumed_tokens, error) = case
        json.parse(res, rpc_message.rpc_response_decoder())
      {
        Ok(RpcResult(result:, ..)) -> {
          case decode.run(result, rpc_result_payload_decoder(ctx.rpc_config)) {
            Ok(array) -> {
              let tokens =
                { array |> list.length() |> int.to_float() } /. 100.0
                |> float.ceiling()
                |> float.round()
              #(tokens, None)
            }
            Error(_) -> #(1, None)
          }
        }
        Ok(RpcError(..)) -> {
          #(1, Some("ERROR: " <> res))
        }
        Error(_) -> {
          #(1, Some("INVALID: " <> res))
        }
      }

      let limit = ctx.ratelimit_cache |> cache.consume(ip, consumed_tokens)

      let elapsed_ms =
        {
          elapsed_time
          |> duration.to_seconds()
        }
        *. 1000.0
        |> float.round()
      let byte_size = res |> string.byte_size()

      io.println(
        "PROXY "
        <> request.method
        <> ": "
        <> elapsed_ms |> int.to_string()
        <> "ms, "
        <> byte_size |> int.to_string()
        <> " B, "
        <> consumed_tokens |> int.to_string()
        <> " token"
        <> case consumed_tokens == 1 {
          True -> ""
          False -> "s"
        }
        <> case error {
          Some(err) -> ", " <> err
          None -> ""
        },
      )

      storage.insert_log(
        ctx.db,
        request.method,
        elapsed_ms,
        byte_size,
        consumed_tokens,
        error,
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
  ratelimit_cache: Cache,
  ip: String,
  request: RpcRequest,
  next: fn() -> Response,
) -> Response {
  let #(remaining_tokens, reset) = cache.check(ratelimit_cache, ip)
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

fn check_method_allowlist(
  request: RpcRequest,
  opts: RpcConfig,
  next: fn() -> Response,
) -> Response {
  case opts.method_allowlist {
    AllMethods -> next()
    SomeMethods(list) ->
      case list |> list.contains(request.method) {
        True -> next()
        False ->
          wisp.bad_request()
          |> wisp.string_body(rpc_message.encode_rpc_error(
            request.id,
            "Method not allowed",
          ))
      }
  }
}

fn landing_page(opts: ServerConfig) -> Response {
  // TODO: Add a landing page
  wisp.ok()
  |> wisp.string_body(opts.title <> "\n\n" <> opts.description)
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

// Recursively build a decoder for the RPC result payload at the given path
fn rpc_result_payload_decoder(opts: RpcConfig) -> Decoder(List(Dynamic)) {
  rpc_result_payload_decoder_impl(opts.payload_path)
}

fn rpc_result_payload_decoder_impl(path: List(String)) -> Decoder(List(Dynamic)) {
  case path {
    [] -> decode.list(decode.dynamic)
    [field, ..rest] -> {
      use payload <- decode.field(field, rpc_result_payload_decoder_impl(rest))
      decode.success(payload)
    }
  }
}
