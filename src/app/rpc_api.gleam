import gleam/bit_array
import gleam/http
import gleam/http/request
import gleam/httpc
import gleam/int
import gleam/result

import app/context.{type RpcConnection}

/// Make a request to the PokeAPI.
pub fn make_request(
  body: String,
  rpc_connection: RpcConnection,
) -> Result(String, String) {
  let assert Ok(req) = request.to(rpc_connection.url)

  let req =
    req
    |> request.set_method(http.Post)
    |> request.set_header("content-type", "application/json")
    |> request.set_body(body)

  // HTTP Basic Auth
  let auth = rpc_connection.username <> ":" <> rpc_connection.password
  let req =
    req
    |> request.set_header(
      "authorization",
      "Basic " <> bit_array.from_string(auth) |> bit_array.base64_encode(True),
    )

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
