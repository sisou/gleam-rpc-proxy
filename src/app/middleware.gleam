import gleam/bit_array
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

import app/cache.{type Cache}
import app/config.{type RpcConfig, AllMethods, SomeMethods}
import app/rpc_message.{type RpcRequest}
import app/utils

import wisp.{type Request, type Response}

pub fn require_ip(req: Request, next: fn(String) -> Response) -> Response {
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
    None ->
      wisp.bad_request()
      |> wisp.set_header("content-type", "text/plain")
      |> wisp.string_body("Missing IP address")
  }
}

pub fn check_ratelimit(
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
      |> wisp.set_header("content-type", "application/json")
      |> utils.add_ratelimit_headers(remaining_tokens, reset)
      |> wisp.string_body(rpc_message.encode_rpc_error(
        request.id,
        "Rate limit exceeded",
      ))
  }
}

pub fn decode_request_body(
  body: String,
  next: fn(RpcRequest) -> Response,
) -> Response {
  case json.parse(body, rpc_message.rpc_request_decoder()) {
    Ok(request) -> next(request)
    Error(_) ->
      wisp.bad_request()
      |> wisp.set_header("content-type", "text/plain")
      |> wisp.string_body("Invalid JSON-RPC request")
  }
}

pub fn check_method_allowlist(
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
          |> wisp.set_header("content-type", "application/json")
          |> wisp.string_body(rpc_message.encode_rpc_error(
            request.id,
            "Method not allowed",
          ))
      }
  }
}

pub fn basic_auth(
  req: Request,
  auth: Option(#(String, String)),
  next: fn() -> Response,
) -> Response {
  case auth {
    None -> next()
    Some(#(username, password)) ->
      case validate_basic_auth(req, #(username, password)) {
        Ok(_) -> next()
        Error(_) ->
          wisp.response(401) |> wisp.set_header("www-authenticate", "Basic")
      }
  }
}

fn validate_basic_auth(
  req: Request,
  auth: #(String, String),
) -> Result(Nil, Nil) {
  use #(_, value) <- result.try(
    req.headers |> list.find(fn(pair) { pair.0 == "authorization" }),
  )
  case value {
    "Basic " <> encoded -> {
      use bits <- result.try(bit_array.base64_decode(encoded))
      use decoded <- result.try(bits |> bit_array.to_string())
      use #(user, pass) <- result.try(decoded |> string.split_once(":"))
      case user == auth.0 && pass == auth.1 {
        True -> Ok(Nil)
        False -> Error(Nil)
      }
    }
    _ -> Error(Nil)
  }
}
