import gleam/int
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

import envoy

pub type MethodAllowlist {
  AllMethods
  SomeMethods(List(String))
}

pub type RpcConfig {
  RpcConfig(
    url: String,
    username: Option(String),
    password: Option(String),
    payload_path: List(String),
    method_allowlist: MethodAllowlist,
  )
}

pub fn rpc_config() -> RpcConfig {
  let assert Ok(rpc_url) = envoy.get("RPC_URL")
  let rpc_username = envoy.get("RPC_USERNAME") |> option.from_result()
  let rpc_password = envoy.get("RPC_PASSWORD") |> option.from_result()
  let rpc_payload_path =
    envoy.get("RESULT_PAYLOAD_PATH") |> result.unwrap("") |> string.split(".")
  let rpc_method_allowlist = case
    envoy.get("METHOD_ALLOWLIST") |> result.unwrap("")
  {
    "" -> SomeMethods([])
    "*" -> AllMethods
    data -> SomeMethods(data |> string.split(","))
  }

  RpcConfig(
    url: rpc_url,
    username: rpc_username,
    password: rpc_password,
    payload_path: rpc_payload_path,
    method_allowlist: rpc_method_allowlist,
  )
}

pub type RatelimitConfig {
  RatelimitConfig(initial_tokens: Int, duration_seconds: Int)
}

pub fn ratelimit_config() -> RatelimitConfig {
  let ratelimit_bucket_size =
    envoy.get("RATELIMIT_BUCKET_SIZE")
    |> result.map(int.parse)
    |> result.flatten()
    |> result.unwrap(20)
  let ratelimit_bucket_duration =
    envoy.get("RATELIMIT_BUCKET_DURATION")
    |> result.map(int.parse)
    |> result.flatten()
    |> result.unwrap(10)

  RatelimitConfig(
    initial_tokens: ratelimit_bucket_size,
    duration_seconds: ratelimit_bucket_duration,
  )
}

pub type ServerConfig {
  ServerConfig(host: String, port: Int, title: String, description: String)
}

pub fn server_config() -> ServerConfig {
  let host = envoy.get("HOST") |> result.unwrap("localhost")
  let port =
    envoy.get("PORT")
    |> result.map(int.parse)
    |> result.flatten()
    |> result.unwrap(8000)

  let title =
    envoy.get("SERVICE_TITLE") |> result.unwrap("Public JSON-RPC Server")
  let description =
    envoy.get("SERVICE_DESCRIPTION")
    |> result.unwrap("Free rate-limited JSON-RPC access")

  ServerConfig(host:, port:, title:, description:)
}

pub type SqliteConfig {
  SqliteConfig(path: String)
}

pub fn sqlite_config() -> SqliteConfig {
  let path = envoy.get("SQLITE_PATH") |> result.unwrap(":memory:")

  SqliteConfig(path:)
}

pub type MetricsConfig {
  MetricsConfig(enabled: Bool, auth: Option(#(String, String)))
}

pub fn metrics_config() -> MetricsConfig {
  let enabled =
    envoy.get("METRICS_ENABLED")
    |> result.map(fn(_) { True })
    |> result.unwrap(False)
  let username = envoy.get("METRICS_USERNAME") |> option.from_result()
  let password = envoy.get("METRICS_PASSWORD") |> option.from_result()
  let auth = case username, password {
    Some(username), Some(password) -> Some(#(username, password))
    Some(_), None -> panic as "Missing METRICS_PASSWORD"
    None, Some(_) -> panic as "Missing METRICS_USERNAME"
    _, _ -> None
  }

  MetricsConfig(enabled:, auth:)
}
