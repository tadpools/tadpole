//// REST builders, rate-limit header parsing, response checks.

import gleam/option.{None, Some}
import gleeunit/should
import tadpole/rest

pub fn get_request_defaults_test() {
  let req = rest.get("/users/@me")
  req.method |> should.equal(rest.GET)
  req.path |> should.equal("/users/@me")
  req.body |> should.equal(None)
}

pub fn post_request_carries_body_test() {
  let req = rest.post("/channels/123/messages", "{\"content\":\"hi\"}")
  req.method |> should.equal(rest.POST)
  req.body |> should.equal(Some("{\"content\":\"hi\"}"))
}

pub fn patch_request_test() {
  let req = rest.patch("/channels/123/messages/456", "{\"content\":\"edited\"}")
  req.method |> should.equal(rest.PATCH)
  req.body |> should.equal(Some("{\"content\":\"edited\"}"))
}

pub fn delete_request_has_no_body_test() {
  let req = rest.delete("/channels/123/messages/456")
  req.method |> should.equal(rest.DELETE)
  req.body |> should.equal(None)
}

pub fn with_header_prepends_test() {
  let req =
    rest.get("/users/@me")
    |> rest.with_header("X-Custom", "value")

  req.headers |> should.equal([#("X-Custom", "value")])
}

pub fn with_audit_log_reason_test() {
  let req =
    rest.delete("/channels/123/messages/456")
    |> rest.with_audit_log_reason("spam removal")

  req.audit_log_reason |> should.equal(Some("spam removal"))
}

pub fn authorization_header_format_test() {
  rest.authorization_header("MYTOKEN")
  |> should.equal(#("Authorization", "Bot MYTOKEN"))
}

pub fn parse_full_rate_limit_headers_test() {
  let parsed =
    rest.parse_rate_limit_headers([
      #("X-RateLimit-Limit", "5"),
      #("X-RateLimit-Remaining", "0"),
      #("X-RateLimit-Reset", "1470173023"),
      #("X-RateLimit-Reset-After", "1.420"),
      #("X-RateLimit-Bucket", "abcd1234"),
      #("X-RateLimit-Policy", "user"),
    ])

  parsed.limit |> should.equal(Some(5))
  parsed.remaining |> should.equal(Some(0))
  parsed.reset |> should.equal(Some(1_470_173_023.0))
  parsed.bucket |> should.equal(Some("abcd1234"))
  parsed.scope |> should.equal(None)
}

pub fn parse_fractional_reset_test() {
  // The docs' reset is an epoch timestamp that may carry a fractional
  // part; parsing it as an integer used to drop the whole field.
  let parsed =
    rest.parse_rate_limit_headers([#("X-RateLimit-Reset", "1470173023.125")])

  parsed.reset |> should.equal(Some(1_470_173_023.125))
}

pub fn parse_scope_header_test() {
  // The docs name exactly three scopes, lowercase.
  rest.parse_rate_limit_headers([#("X-RateLimit-Scope", "user")]).scope
  |> should.equal(Some(rest.ScopeUser))

  rest.parse_rate_limit_headers([#("X-RateLimit-Scope", "shared")]).scope
  |> should.equal(Some(rest.ScopeShared))

  rest.parse_rate_limit_headers([#("X-RateLimit-Scope", "global")]).scope
  |> should.equal(Some(rest.ScopeGlobal))
}

pub fn parse_unknown_scope_degrades_to_none_test() {
  // An unknown scope is no knowledge, not a guess.
  rest.parse_rate_limit_headers([#("X-RateLimit-Scope", "bot")]).scope
  |> should.equal(None)

  rest.parse_rate_limit_headers([#("X-RateLimit-Scope", "USER")]).scope
  |> should.equal(None)
}

pub fn parse_scope_absent_is_none_test() {
  // Most responses carry no scope header: it defaults to user.
  rest.parse_rate_limit_headers([#("X-RateLimit-Limit", "5")]).scope
  |> should.equal(None)
}

pub fn parse_missing_rate_limit_headers_test() {
  let parsed =
    rest.parse_rate_limit_headers([#("Content-Type", "application/json")])

  parsed.limit |> should.equal(None)
  parsed.remaining |> should.equal(None)
  parsed.bucket |> should.equal(None)
  parsed.is_global |> should.be_false
}

pub fn parse_retry_after_header_test() {
  let parsed = rest.parse_rate_limit_headers([#("Retry-After", "1478")])

  parsed.retry_after |> should.equal(Some(1478))
}

pub fn parse_global_flag_test() {
  let global = rest.parse_rate_limit_headers([#("X-RateLimit-Global", "true")])
  let scoped = rest.parse_rate_limit_headers([#("X-RateLimit-Global", "false")])

  global.is_global |> should.be_true
  scoped.is_global |> should.be_false
}

pub fn malformed_header_values_degrade_to_none_test() {
  let parsed =
    rest.parse_rate_limit_headers([
      #("X-RateLimit-Limit", "not-a-number"),
      #("X-RateLimit-Reset-After", "not-a-float"),
    ])

  parsed.limit |> should.equal(None)
  parsed.reset_after |> should.equal(None)
}

pub fn classify_429_as_rate_limited_test() {
  rest.is_rate_limited(make_response(429)) |> should.be_true
}

pub fn classify_400_as_client_error_test() {
  let response = make_response(400)
  rest.is_client_error(response) |> should.be_true
  rest.is_rate_limited(response) |> should.be_false
}

pub fn classify_401_as_unauthorized_test() {
  rest.is_unauthorized(make_response(401)) |> should.be_true
}

pub fn classify_403_as_forbidden_test() {
  rest.is_forbidden(make_response(403)) |> should.be_true
}

pub fn classify_404_as_not_found_test() {
  rest.is_not_found(make_response(404)) |> should.be_true
}

pub fn classify_500_as_server_error_test() {
  let response = make_response(500)
  rest.is_server_error(response) |> should.be_true
  rest.is_client_error(response) |> should.be_false
}

pub fn classify_200_as_none_of_the_errors_test() {
  let response = make_response(200)
  rest.is_rate_limited(response) |> should.be_false
  rest.is_client_error(response) |> should.be_false
  rest.is_server_error(response) |> should.be_false
  rest.is_unauthorized(response) |> should.be_false
  rest.is_ok(response) |> should.be_true
}

fn make_response(status: Int) -> rest.RestResponse {
  rest.RestResponse(
    status: status,
    headers: [],
    body: "{}",
    rate_limit_headers: None,
  )
}
