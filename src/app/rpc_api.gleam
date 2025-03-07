import gleam/bit_array
import gleam/http
import gleam/http/request
import gleam/httpc
import gleam/int
import gleam/option.{None}
import gleam/result

import app/config.{type RpcConfig}

/// Make a request to the PokeAPI.
pub fn make_request(body: String, opts: RpcConfig) -> Result(String, String) {
  let assert Ok(req) = request.to(opts.url)

  let req =
    req
    |> request.set_method(http.Post)
    |> request.set_header("content-type", "application/json")
    |> request.set_body(body)

  // HTTP Basic Auth
  let req = case opts.username, opts.password {
    None, None -> req
    _, _ -> {
      let auth =
        opts.username |> option.unwrap("")
        <> ":"
        <> opts.password |> option.unwrap("")
      req
      |> request.set_header(
        "authorization",
        "Basic " <> bit_array.from_string(auth) |> bit_array.base64_encode(True),
      )
    }
  }

  let resp =
    httpc.send(req)
    |> result.map_error(fn(err) {
      case err {
        httpc.InvalidUtf8Response -> "Invalid UTF-8 response from RPC server"
        httpc.FailedToConnect(ip4, _ip6) -> {
          case ip4 {
            httpc.Posix(code) ->
              "Failed to connect to RPC server (IPv4): " <> code
            httpc.TlsAlert(code, detail) ->
              "Failed to connect to RPC server (IPv4): "
              <> code
              <> " "
              <> detail
          }
        }
      }
    })

  use resp <- result.try(resp)

  case resp.status {
    200 -> Ok(resp.body)
    _ ->
      Error("Got status " <> int.to_string(resp.status) <> " from RPC server")
  }
}
