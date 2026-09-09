//// Executor tests: every transport is synthetic, sleep is recorded, no
//// network. The recorder (tadpole_test_ffi) keeps per-test lists of the
//// http requests seen and of the sleeps in order, so retry and gating
//// behaviour is asserted by counting, not by timing.

import gleam/http
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleeunit/should
import tadpole/error
import tadpole/rest
import tadpole/rest/execute

@external(erlang, "tadpole_test_ffi", "record_request")
fn record_request(request: Request(String)) -> Nil

@external(erlang, "tadpole_test_ffi", "record_event")
fn record_event(event: String) -> Nil

@external(erlang, "tadpole_test_ffi", "requests")
fn recorded_requests() -> List(Request(String))

@external(erlang, "tadpole_test_ffi", "events")
fn recorded_events() -> List(String)

@external(erlang, "tadpole_test_ffi", "reset")
fn reset_recorder() -> Nil

@external(erlang, "tadpole_test_ffi", "queue")
fn queue_response(response: Response(String)) -> Nil

@external(erlang, "tadpole_test_ffi", "next")
fn next_response() -> Result(Response(String), Nil)

// fixtures

const token = "faketoken_faketoken_faketoken_1234"

fn client() -> rest.RestClient {
  rest.new_client(token, 5000, True, 2)
}

fn no_retry_client() -> rest.RestClient {
  rest.new_client(token, 5000, False, 2)
}

fn response(
  status: Int,
  headers: List(#(String, String)),
  body: String,
) -> Response(String) {
  response.Response(status: status, headers: headers, body: body)
}

fn transport(responses: List(Response(String))) -> execute.Transport {
  list.each(responses, queue_response)
  fn(request) {
    record_request(request)
    record_event("request " <> http.method_to_string(request.method))
    case next_response() {
      Ok(canned) -> Ok(canned)
      // a call past the script is a loud failure, never a replayed one
      Error(_) -> Error(execute.ResponseTimeout)
    }
  }
}

fn failing_transport(failure: execute.TransportError) -> execute.Transport {
  fn(request) {
    record_request(request)
    Error(failure)
  }
}

/// The sleep send_with_sleep gets: records instead of waiting.
fn recording_sleep(ms: Int) -> Nil {
  record_event("sleep " <> int.to_string(ms))
}

const user_payload = "{\"id\":\"900000000000000123\",\"username\":\"lilypad_bot\",\"global_name\":\"Lilypad\",\"avatar\":null,\"bot\":true,\"system\":false}"

const four_twenty_nine_body = "{\"message\":\"You are being rate limited.\",\"code\":429,\"global\":false}"

// 2xx

pub fn ok_200_returns_parsed_response_test() {
  reset_recorder()
  let headers = [
    #("X-RateLimit-Limit", "5"),
    #("X-RateLimit-Remaining", "4"),
    #("X-RateLimit-Bucket", "bckt-ok"),
  ]

  let assert Ok(parsed) =
    execute.send_with_sleep(
      client(),
      rest.get("/users/@me"),
      transport([response(200, headers, user_payload)]),
      recording_sleep,
    )

  parsed.status |> should.equal(200)
  parsed.body |> should.equal(user_payload)
  let assert Some(limit) = parsed.rate_limit_headers
  limit.limit |> should.equal(Some(5))
  limit.remaining |> should.equal(Some(4))
  limit.bucket |> should.equal(Some("bckt-ok"))
}

pub fn ok_response_records_one_send_no_sleep_test() {
  reset_recorder()

  let assert Ok(_) =
    execute.send_with_sleep(
      client(),
      rest.get("/users/@me"),
      transport([response(200, [], "{}")]),
      recording_sleep,
    )

  recorded_events() |> should.equal(["request GET"])
}

// non-2xx

pub fn unauthorized_401_carries_discord_code_and_body_test() {
  reset_recorder()
  let body = "{\"message\": \"Invalid authentication token\", \"code\": 0}"

  let assert Error(error.RestStatus(route, status, code, stored)) =
    execute.send_with_sleep(
      client(),
      rest.get("/users/@me"),
      transport([response(401, [], body)]),
      recording_sleep,
    )

  error.route_to_string(route) |> should.equal("GET /users/@me")
  status |> should.equal(401)
  code |> should.equal(Some(0))
  stored |> should.equal(Some(body))
}

pub fn error_body_missing_fields_degrade_to_none_test() {
  reset_recorder()

  let assert Error(error.RestStatus(_, status, code, stored)) =
    execute.send_with_sleep(
      client(),
      rest.get("/users/@me"),
      transport([response(403, [], "you shall not pass")]),
      recording_sleep,
    )

  status |> should.equal(403)
  code |> should.equal(None)
  stored |> should.equal(Some("you shall not pass"))
}

pub fn server_error_500_maps_to_rest_status_test() {
  reset_recorder()

  let assert Error(error.RestStatus(_, status, _, _)) =
    execute.send_with_sleep(
      client(),
      rest.get("/users/@me"),
      transport([response(500, [], "{}")]),
      recording_sleep,
    )

  status |> should.equal(500)
}

// transport failures

pub fn timeout_maps_to_synthetic_status_zero_test() {
  reset_recorder()

  let assert Error(error.RestStatus(_, status, code, Some(body))) =
    execute.send_with_sleep(
      client(),
      rest.get("/users/@me"),
      failing_transport(execute.ResponseTimeout),
      recording_sleep,
    )

  status |> should.equal(0)
  code |> should.equal(None)
  body
  |> should.equal("no HTTP response: no response within the client timeout")
}

pub fn failed_to_connect_maps_both_stack_details_test() {
  reset_recorder()
  let failure =
    execute.FailedToConnect(
      ip4: execute.Posix("econnrefused"),
      ip6: execute.TlsAlert("certificate_expired", "expired"),
    )

  let assert Error(error.RestStatus(_, 0, None, Some(body))) =
    execute.send_with_sleep(
      client(),
      rest.get("/users/@me"),
      failing_transport(failure),
      recording_sleep,
    )

  body
  |> should.equal(
    "no HTTP response: failed to connect (ipv4: econnrefused, ipv6: certificate_expired expired)",
  )
}

// 429 handling

pub fn rate_limited_retries_then_succeeds_test() {
  reset_recorder()

  let assert Ok(parsed) =
    execute.send_with_sleep(
      client(),
      rest.get("/users/@me"),
      transport([
        response(429, [#("Retry-After", "2")], four_twenty_nine_body),
        response(200, [], user_payload),
      ]),
      recording_sleep,
    )

  parsed.status |> should.equal(200)
  // header seconds -> ms; the gate on the retry round re-checks the same
  // window against elapsed, so it must not sleep twice
  recorded_events()
  |> should.equal(["request GET", "sleep 2000", "request GET"])
}

pub fn retries_exhausted_maps_to_rate_limited_test() {
  reset_recorder()
  let limited = fn() {
    response(
      429,
      [
        #("Retry-After", "3"),
        #("X-RateLimit-Global", "true"),
        #("X-RateLimit-Bucket", "bckt-x"),
      ],
      four_twenty_nine_body,
    )
  }

  let assert Error(error.RateLimited(route, retry_ms, is_global, bucket)) =
    execute.send_with_sleep(
      client(),
      rest.get("/users/@me"),
      transport([limited(), limited(), limited()]),
      recording_sleep,
    )

  // max_retries 2 -> initial send plus two retries, then give up; a
  // fourth send would hit the empty queue and answer with a timeout
  list.length(recorded_requests()) |> should.equal(3)
  error.route_to_string(route) |> should.equal("GET /users/@me")
  retry_ms |> should.equal(3000)
  is_global |> should.equal(True)
  let assert Some(bucket_id) = bucket
  error.bucket_id_to_string(bucket_id) |> should.equal("bckt-x")
}

pub fn retry_disabled_means_single_attempt_test() {
  reset_recorder()

  let assert Error(error.RateLimited(_, retry_ms, False, None)) =
    execute.send_with_sleep(
      no_retry_client(),
      rest.get("/users/@me"),
      transport([response(429, [#("Retry-After", "3")], four_twenty_nine_body)]),
      recording_sleep,
    )

  list.length(recorded_requests()) |> should.equal(1)
  retry_ms |> should.equal(3000)
  recorded_events() |> should.equal(["request GET"])
}

pub fn retry_after_falls_back_to_body_field_test() {
  reset_recorder()
  let body =
    "{\"message\":\"You are being rate limited.\",\"code\":429,\"global\":false,\"retry_after\":1.5}"

  let assert Ok(_) =
    execute.send_with_sleep(
      client(),
      rest.get("/users/@me"),
      transport([
        response(429, [], body),
        response(200, [], user_payload),
      ]),
      recording_sleep,
    )

  // Discord's body retry_after is fractional seconds -> 1500ms
  recorded_events()
  |> should.equal(["request GET", "sleep 1500", "request GET"])
}

// request shape

pub fn request_shape_get_test() {
  reset_recorder()

  let _ =
    execute.send_with_sleep(
      client(),
      rest.get("/users/@me"),
      transport([response(200, [], user_payload)]),
      recording_sleep,
    )

  let assert [sent] = recorded_requests()
  sent.method |> should.equal(http.Get)
  sent.path |> should.equal("/api/v10/users/@me")
  sent.host |> should.equal("discord.com")
  rest.header(sent.headers, "authorization")
  |> should.equal(Some("Bot " <> token))
  rest.header(sent.headers, "user-agent")
  |> should.equal(Some("tadpole (Gleam Discord library)"))
  rest.header(sent.headers, "content-type") |> should.equal(None)
}

pub fn request_shape_post_carries_content_type_test() {
  reset_recorder()
  let channel = "742300000000000001"

  let _ =
    execute.send_with_sleep(
      client(),
      rest.post("/channels/" <> channel <> "/messages", "{\"content\":\"hi\"}"),
      transport([response(200, [], "{}")]),
      recording_sleep,
    )

  let assert [sent] = recorded_requests()
  sent.method |> should.equal(http.Post)
  sent.path |> should.equal("/api/v10/channels/742300000000000001/messages")
  rest.header(sent.headers, "content-type")
  |> should.equal(Some("application/json"))
  sent.body |> should.equal("{\"content\":\"hi\"}")
}

pub fn audit_log_reason_is_percent_encoded_test() {
  reset_recorder()
  let request =
    rest.delete("/channels/742300000000000001/messages/987654321012345678")
    |> rest.with_audit_log_reason("spam removal")

  let _ =
    execute.send_with_sleep(
      client(),
      request,
      transport([response(200, [], "{}")]),
      recording_sleep,
    )

  let assert [sent] = recorded_requests()
  rest.header(sent.headers, "x-audit-log-reason")
  |> should.equal(Some("spam%20removal"))
}

pub fn unset_audit_log_reason_sends_no_header_test() {
  reset_recorder()

  let _ =
    execute.send_with_sleep(
      client(),
      rest.delete("/channels/742300000000000001/messages/987654321012345678"),
      transport([response(200, [], "{}")]),
      recording_sleep,
    )

  let assert [sent] = recorded_requests()
  rest.header(sent.headers, "x-audit-log-reason") |> should.equal(None)
}

// pre-send gate

pub fn exhausted_bucket_gates_the_next_send_test() {
  reset_recorder()
  let seeded =
    response(
      200,
      [
        #("X-RateLimit-Remaining", "0"),
        #("X-RateLimit-Reset-After", "5.0"),
        #("X-RateLimit-Bucket", "bckt-gate"),
      ],
      "{}",
    )
  let request = rest.get("/users/@me")
  // one transport answers both sends: the seed, then a plain 200
  let gated_transport = transport([seeded, response(200, [], "{}")])
  let session = execute.new_session(client())

  // the first send went out immediately; limits are discovered, not
  // predicted, so only the second send meets a gate
  let assert #(Ok(_), session) =
    execute.send_in_session(session, request, gated_transport, recording_sleep)
  recorded_events() |> should.equal(["request GET"])

  let assert #(Ok(_), _) =
    execute.send_in_session(session, request, gated_transport, recording_sleep)

  recorded_events()
  |> should.equal(["request GET", "sleep 5000", "request GET"])
}

pub fn first_call_to_unknown_route_never_waits_test() {
  reset_recorder()

  let _ =
    execute.send_with_sleep(
      client(),
      rest.get("/users/@me"),
      transport([response(200, [], "{}")]),
      recording_sleep,
    )

  recorded_events() |> should.equal(["request GET"])
}
