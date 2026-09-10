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

/// Whose limit a rate limit response describes, per the docs'
/// X-RateLimit-Scope header: `user` (this app alone, the default),
/// `shared` (the bucket is shared with other apps), or `global` (every
/// route, every app).
pub type RateLimitScope {
  ScopeUser
  ScopeShared
  ScopeGlobal
}

pub type RateLimitHeaders {
  RateLimitHeaders(
    limit: Option(Int),
    remaining: Option(Int),
    /// Epoch seconds. Discord may send a fractional part, so this is a
    /// float even though most responses carry a whole number.
    reset: Option(Float),
    reset_after: Option(Float),
    bucket: Option(String),
    retry_after: Option(Int),
    is_global: Bool,
    /// None when the header is absent or names a value the docs do
    /// not: the three known scopes are user, shared, global.
    scope: Option(RateLimitScope),
  )
}

/// Discord may omit any of these headers; each degrades to None.
pub fn parse_rate_limit_headers(
  headers: List(#(String, String)),
) -> RateLimitHeaders {
  RateLimitHeaders(
    limit: header_int(headers, "X-RateLimit-Limit"),
    remaining: header_int(headers, "X-RateLimit-Remaining"),
    reset: header_seconds(headers, "X-RateLimit-Reset"),
    reset_after: header_seconds(headers, "X-RateLimit-Reset-After"),
    bucket: header(headers, "X-RateLimit-Bucket"),
    retry_after: header_int(headers, "Retry-After"),
    is_global: case header(headers, "X-RateLimit-Global") {
      Some(value) -> value == "true"
      None -> False
    },
    scope: parse_scope(header(headers, "X-RateLimit-Scope")),
  )
}

/// The docs name exactly three scope values, lowercase. Anything else
/// degrades to None, the same treatment a missing header gets: an
/// unknown scope is no knowledge, not a guess.
fn parse_scope(value: Option(String)) -> Option(RateLimitScope) {
  case value {
    Some("user") -> Some(ScopeUser)
    Some("shared") -> Some(ScopeShared)
    Some("global") -> Some(ScopeGlobal)
    _ -> None
  }
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

/// A seconds value that may arrive whole ("1470173023") or fractional
/// ("1470173023.125"): Discord's reset timestamps are epoch seconds and
/// may carry a fractional part, while float.parse demands the point.
/// Anything that parses as neither is None.
fn header_seconds(
  headers: List(#(String, String)),
  name: String,
) -> Option(Float) {
  case header(headers, name) {
    None -> None
    Some(value) ->
      case int.parse(value) {
        Ok(whole) -> Some(int.to_float(whole))
        Error(_) -> float.parse(value) |> option.from_result
      }
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
