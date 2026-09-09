//// REST request builders, rate-limit header parsing, response checks.
//// Rate-limit state is derived from response headers and 429 bodies,
//// never from a hardcoded table.

import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

pub type Method {
  GET
  POST
  PUT
  DELETE
  PATCH
  HEAD
  OPTIONS
}

pub type RestClient {
  RestClient(
    token: String,
    timeout_ms: Int,
    retry_on_429: Bool,
    max_retries: Int,
  )
}

pub fn new_client(
  token: String,
  timeout_ms: Int,
  retry_on_429: Bool,
  max_retries: Int,
) -> RestClient {
  RestClient(
    token: token,
    timeout_ms: timeout_ms,
    retry_on_429: retry_on_429,
    max_retries: max_retries,
  )
}

pub type RestRequest {
  RestRequest(
    method: Method,
    path: String,
    headers: List(#(String, String)),
    body: Option(String),
    audit_log_reason: Option(String),
  )
}

pub fn get(path: String) -> RestRequest {
  RestRequest(
    method: GET,
    path: path,
    headers: [],
    body: None,
    audit_log_reason: None,
  )
}

pub fn post(path: String, body: String) -> RestRequest {
  RestRequest(
    method: POST,
    path: path,
    headers: [],
    body: Some(body),
    audit_log_reason: None,
  )
}

pub fn put(path: String, body: String) -> RestRequest {
  RestRequest(
    method: PUT,
    path: path,
    headers: [],
    body: Some(body),
    audit_log_reason: None,
  )
}

pub fn patch(path: String, body: String) -> RestRequest {
  RestRequest(
    method: PATCH,
    path: path,
    headers: [],
    body: Some(body),
    audit_log_reason: None,
  )
}

pub fn delete(path: String) -> RestRequest {
  RestRequest(
    method: DELETE,
    path: path,
    headers: [],
    body: None,
    audit_log_reason: None,
  )
}

pub fn with_header(
  request: RestRequest,
  name: String,
  value: String,
) -> RestRequest {
  RestRequest(..request, headers: [#(name, value), ..request.headers])
}

pub fn with_audit_log_reason(
  request: RestRequest,
  reason: String,
) -> RestRequest {
  RestRequest(..request, audit_log_reason: Some(reason))
}

pub fn authorization_header(token: String) -> #(String, String) {
  #("Authorization", "Bot " <> token)
}

pub type RestResponse {
  RestResponse(
    status: Int,
    headers: List(#(String, String)),
    body: String,
    rate_limit_headers: Option(RateLimitHeaders),
  )
}

pub type RateLimitHeaders {
  RateLimitHeaders(
    limit: Option(Int),
    remaining: Option(Int),
    reset: Option(Int),
    reset_after: Option(Float),
    bucket: Option(String),
    retry_after: Option(Int),
    is_global: Bool,
  )
}

/// Discord may omit any of these headers; each degrades to None.
pub fn parse_rate_limit_headers(
  headers: List(#(String, String)),
) -> RateLimitHeaders {
  RateLimitHeaders(
    limit: header_int(headers, "X-RateLimit-Limit"),
    remaining: header_int(headers, "X-RateLimit-Remaining"),
    reset: header_int(headers, "X-RateLimit-Reset"),
    reset_after: header_float(headers, "X-RateLimit-Reset-After"),
    bucket: header(headers, "X-RateLimit-Bucket"),
    retry_after: header_int(headers, "Retry-After"),
    is_global: case header(headers, "X-RateLimit-Global") {
      Some(value) -> value == "true"
      None -> False
    },
  )
}

/// Case-insensitive: HTTP header names are case-insensitive per spec, and
/// proxies/clients normalize casing unpredictably.
pub fn header(
  headers: List(#(String, String)),
  name: String,
) -> Option(String) {
  let wanted = string.lowercase(name)
  case list.find(headers, fn(pair) { string.lowercase(pair.0) == wanted }) {
    Ok(#(_, value)) -> Some(value)
    Error(_) -> None
  }
}

fn header_int(headers: List(#(String, String)), name: String) -> Option(Int) {
  case header(headers, name) {
    Some(value) -> int.parse(value) |> option.from_result
    None -> None
  }
}

fn header_float(
  headers: List(#(String, String)),
  name: String,
) -> Option(Float) {
  case header(headers, name) {
    Some(value) -> float.parse(value) |> option.from_result
    None -> None
  }
}

pub fn is_rate_limited(response: RestResponse) -> Bool {
  response.status == 429
}

pub fn is_client_error(response: RestResponse) -> Bool {
  response.status >= 400 && response.status < 500
}

pub fn is_server_error(response: RestResponse) -> Bool {
  response.status >= 500 && response.status < 600
}

pub fn is_unauthorized(response: RestResponse) -> Bool {
  response.status == 401
}

pub fn is_forbidden(response: RestResponse) -> Bool {
  response.status == 403
}

pub fn is_not_found(response: RestResponse) -> Bool {
  response.status == 404
}

pub fn is_ok(response: RestResponse) -> Bool {
  response.status >= 200 && response.status < 300
}
