import app/cache.{type Cache}

pub type RpcConnection {
  RpcConnection(url: String, username: String, password: String)
}

/// A simple context type that can be attached to
/// each request to provide access to the cache.
pub type Context {
  Context(ratelimit_cache: Cache, rpc_connection: RpcConnection)
}
