import gleam/erlang/process
import gleam/int
import gleam/result

import app/cache
import app/context.{Context}
import app/manager
import app/router

import dotenv_gleam
import envoy
import mist
import wisp
import wisp/wisp_mist

pub fn main() {
  // Set up the Wisp logger for Erlang
  wisp.configure_logger()
  let secret_key_base = wisp.random_string(64)

  // Create the caches and assign them to the context
  let assert Ok(ratelimit_cache) = cache.new()

  dotenv_gleam.config()
  let assert Ok(rpc_url) = envoy.get("RPC_URL")
  let assert Ok(rpc_username) = envoy.get("RPC_USERNAME")
  let assert Ok(rpc_password) = envoy.get("RPC_PASSWORD")
  let rpc_connection =
    context.RpcConnection(rpc_url, rpc_username, rpc_password)

  let context = Context(ratelimit_cache:, rpc_connection:)

  // Create a handler using the function capture syntax.
  // This is similar to a partial application in other languages.
  let handler = router.handle_request(_, context)

  // Start manager in the background
  manager.start(ratelimit_cache)

  // Start the Mist server
  let assert Ok(_) =
    wisp_mist.handler(handler, secret_key_base)
    |> mist.new
    |> mist.bind(
      envoy.get("HOST")
      |> result.unwrap("localhost"),
    )
    |> mist.port(
      envoy.get("PORT")
      |> result.map(int.parse)
      |> result.flatten()
      |> result.unwrap(8000),
    )
    |> mist.start_http

  // Sleep forever to allow the server to run
  process.sleep_forever()
}
