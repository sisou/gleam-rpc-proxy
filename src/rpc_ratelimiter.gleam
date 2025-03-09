import gleam/erlang/process

import app/cache
import app/config
import app/context.{Context}
import app/manager
import app/router
import app/storage

import dotenv_gleam
import mist
import wisp
import wisp/wisp_mist

pub fn main() {
  // Set up the Wisp logger for Erlang
  wisp.configure_logger()
  let secret_key_base = wisp.random_string(64)

  dotenv_gleam.config()

  // Parse configs
  let rpc_config = config.rpc_config()
  let ratelimit_config = config.ratelimit_config()
  let ratelimit_cache = cache.new(ratelimit_config)
  let server_config = config.server_config()
  let sqlite_config = config.sqlite_config()

  // Start database connection
  let db = storage.start(sqlite_config)

  let context =
    Context(
      ratelimit_cache:,
      rpc_config:,
      ratelimit_config:,
      server_config:,
      db:,
    )

  // Create a handler using the function capture syntax.
  // This is similar to a partial application in other languages.
  let handler = router.handle_request(_, context)

  // Start manager in the background
  manager.start(ratelimit_cache)

  // Start the Mist server
  let assert Ok(_) =
    wisp_mist.handler(handler, secret_key_base)
    |> mist.new
    |> mist.bind(server_config.host)
    |> mist.port(server_config.port)
    |> mist.start_http

  // Sleep forever to allow the server to run
  process.sleep_forever()
}
