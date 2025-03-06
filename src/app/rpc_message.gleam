import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode.{type Decoder}
import gleam/json

pub type RpcId {
  StringId(String)
  IntId(Int)
}

fn rpc_id_decoder() -> Decoder(RpcId) {
  decode.one_of(decode.int |> decode.map(IntId), [
    decode.string |> decode.map(StringId),
  ])
}

pub type RpcRequest {
  RpcRequest(jsonrpc: String, method: String, params: Dynamic, id: RpcId)
}

pub type RpcResponse {
  RpcResult(jsonrpc: String, result: Dynamic, id: RpcId)
  RpcError(jsonrpc: String, error: Dynamic, id: RpcId)
}

pub fn rpc_request_decoder() -> Decoder(RpcRequest) {
  use jsonrpc <- decode.field("jsonrpc", decode.string)
  use method <- decode.field("method", decode.string)
  use params <- decode.optional_field(
    "params",
    dynamic.from([]),
    decode.dynamic,
  )
  use id <- decode.field("id", rpc_id_decoder())
  decode.success(RpcRequest(jsonrpc:, method:, params:, id:))
}

fn rpc_result_message_decoder() -> Decoder(RpcResponse) {
  use jsonrpc <- decode.field("jsonrpc", decode.string)
  use result <- decode.field("result", decode.dynamic)
  use id <- decode.field("id", rpc_id_decoder())
  decode.success(RpcResult(jsonrpc:, result:, id:))
}

fn rpc_error_message_decoder() -> Decoder(RpcResponse) {
  use jsonrpc <- decode.field("jsonrpc", decode.string)
  use error <- decode.field("error", decode.dynamic)
  use id <- decode.field("id", rpc_id_decoder())
  decode.success(RpcError(jsonrpc:, error:, id:))
}

pub fn rpc_response_decoder() -> Decoder(RpcResponse) {
  decode.one_of(rpc_result_message_decoder(), [rpc_error_message_decoder()])
}

pub fn encode_rpc_error(id id: RpcId, message message: String) -> String {
  json.object([
    #("jsonrpc", json.string("2.0")),
    #("error", json.string(message)),
    #("id", case id {
      StringId(id) -> json.string(id)
      IntId(id) -> json.int(id)
    }),
  ])
  |> json.to_string()
}
