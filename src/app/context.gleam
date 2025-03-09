import app/cache.{type Cache}
import app/config.{type RatelimitConfig, type RpcConfig, type ServerConfig}

import sqlight

/// A simple context type that can be attached to
/// each request to provide access to the cache.
pub type Context {
  Context(
    ratelimit_cache: Cache,
    rpc_config: RpcConfig,
    ratelimit_config: RatelimitConfig,
    server_config: ServerConfig,
    db: sqlight.Connection,
  )
}
