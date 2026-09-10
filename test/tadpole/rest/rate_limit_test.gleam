//// Tests for the pure rate-limit state machine. Every header set is
//// synthetic — nothing here is copied from the live API.

import gleam/dict
import gleam/int
import gleam/option.{None, Some}
import gleeunit/should
import tadpole/error
import tadpole/rest
import tadpole/rest/rate_limit

// fixtures

const full_headers = [
  #("X-RateLimit-Limit", "5"),
  #("X-RateLimit-Remaining", "4"),
  #("X-RateLimit-Reset-After", "1.5"),
  #("X-RateLimit-Bucket", "bckt-abc"),
]

fn response(
  status: Int,
  headers: List(#(String, String)),
) -> rest.RestResponse {
  rest.RestResponse(
    status: status,
    headers: headers,
    body: "{}",
    rate_limit_headers: Some(rest.parse_rate_limit_headers(headers)),
  )
}

/// A response whose rate-limit headers were never parsed.
fn unparsed_response(status: Int) -> rest.RestResponse {
  rest.RestResponse(
    status: status,
    headers: [],
    body: "{}",
    rate_limit_headers: None,
  )
}

// route_key

pub fn route_key_masks_snowflake_segments_test() {
  rate_limit.route_key("GET", "/channels/123456789012345678/messages")
  |> should.equal("GET /channels/:id/messages")
}

pub fn route_key_masks_multiple_ids_test() {
  rate_limit.route_key(
    "DELETE",
    "/channels/123456789012345678/messages/987654321012345678",
  )
  |> should.equal("DELETE /channels/:id/messages/:id")
}

pub fn route_key_keeps_short_numbers_test() {
  rate_limit.route_key("GET", "/api/v10/gateway")
  |> should.equal("GET /api/v10/gateway")
}

pub fn route_key_keeps_14_digit_segments_test() {
  rate_limit.route_key("GET", "/users/12345678901234")
  |> should.equal("GET /users/12345678901234")
}

pub fn route_key_masks_15_digit_boundary_test() {
  rate_limit.route_key("GET", "/users/123456789012345")
  |> should.equal("GET /users/:id")
}

pub fn route_key_keeps_non_numeric_segments_test() {
  rate_limit.route_key("GET", "/users/@me/guilds")
  |> should.equal("GET /users/@me/guilds")
}

// update + wait_ms

pub fn empty_state_waits_zero_test() {
  rate_limit.new()
  |> rate_limit.wait_ms(0)
  |> should.equal(0)
}

pub fn headers_absent_is_optimistic_test() {
  let state = rate_limit.update(rate_limit.new(), response(200, []))

  rate_limit.wait_ms(state, 0) |> should.equal(0)
  // no window to decay, so time passing changes nothing
  rate_limit.wait_ms(state, 60_000) |> should.equal(0)
}

pub fn unparsed_response_leaves_state_untouched_test() {
  let state = rate_limit.update(rate_limit.new(), response(200, full_headers))
  let after = rate_limit.update(state, unparsed_response(200))

  after |> should.equal(state)
}

pub fn full_headers_are_folded_test() {
  let state = rate_limit.update(rate_limit.new(), response(200, full_headers))

  state.limit |> should.equal(Some(5))
  state.remaining |> should.equal(Some(4))
  state.reset_after_ms |> should.equal(Some(1.5))
  state.retry_after_ms |> should.equal(None)
  state.bucket |> should.equal(Some(error.bucket_id("bckt-abc")))
}

pub fn exhausted_bucket_waits_reset_after_test() {
  let state =
    rate_limit.update(
      rate_limit.new(),
      response(200, [
        #("X-RateLimit-Remaining", "0"),
        #("X-RateLimit-Reset-After", "2.5"),
      ]),
    )

  rate_limit.wait_ms(state, 0) |> should.equal(2500)
  rate_limit.wait_ms(state, 1200) |> should.equal(1300)
  rate_limit.wait_ms(state, 2500) |> should.equal(0)
  rate_limit.wait_ms(state, 9999) |> should.equal(0)
}

pub fn remaining_tokens_mean_no_wait_test() {
  // reset_after is present but tokens are left: reset windows only matter
  // once the bucket is empty
  let state = rate_limit.update(rate_limit.new(), response(200, full_headers))

  rate_limit.wait_ms(state, 0) |> should.equal(0)
}

pub fn exhausted_without_reset_after_is_optimistic_test() {
  let state =
    rate_limit.update(
      rate_limit.new(),
      response(200, [
        #("X-RateLimit-Remaining", "0"),
      ]),
    )

  rate_limit.wait_ms(state, 0) |> should.equal(0)
}

pub fn rate_limited_waits_retry_after_test() {
  let state =
    rate_limit.update(
      rate_limit.new(),
      response(429, [
        #("Retry-After", "5"),
        #("X-RateLimit-Remaining", "0"),
        #("X-RateLimit-Reset-After", "9.0"),
      ]),
    )

  state.retry_after_ms |> should.equal(Some(5000))
  rate_limit.wait_ms(state, 0) |> should.equal(5000)
  rate_limit.wait_ms(state, 4999) |> should.equal(1)
  rate_limit.wait_ms(state, 5000) |> should.equal(0)
  // the retry window outranks the longer reset_after — see wait_ms doc
  rate_limit.wait_ms(state, 8000) |> should.equal(0)
}

pub fn rate_limited_falls_back_to_reset_after_test() {
  let state =
    rate_limit.update(
      rate_limit.new(),
      response(429, [
        #("X-RateLimit-Remaining", "0"),
        #("X-RateLimit-Reset-After", "2.5"),
      ]),
    )

  state.retry_after_ms |> should.equal(Some(2500))
  rate_limit.wait_ms(state, 0) |> should.equal(2500)
}

pub fn rate_limited_without_any_window_is_optimistic_test() {
  let state = rate_limit.update(rate_limit.new(), response(429, []))

  rate_limit.wait_ms(state, 0) |> should.equal(0)
}

pub fn retry_after_on_success_is_ignored_test() {
  let state =
    rate_limit.update(rate_limit.new(), response(200, [#("Retry-After", "9")]))

  state.retry_after_ms |> should.equal(None)
  rate_limit.wait_ms(state, 0) |> should.equal(0)
}

pub fn fractional_retry_after_falls_back_test() {
  // Discord mostly sends whole seconds; a fractional one fails int.parse
  let state =
    rate_limit.update(
      rate_limit.new(),
      response(429, [
        #("Retry-After", "0.4"),
        #("X-RateLimit-Reset-After", "1.5"),
      ]),
    )

  state.retry_after_ms |> should.equal(Some(1500))
}

// scope

pub fn scope_rides_along_from_headers_test() {
  let state =
    rate_limit.update(
      rate_limit.new(),
      response(200, [
        #("X-RateLimit-Bucket", "abcd1234"),
        #("X-RateLimit-Scope", "shared"),
      ]),
    )

  state.scope |> should.equal(Some(rest.ScopeShared))
  // Scope is data, not a wait: a shared limit waits like a user one.
  rate_limit.wait_ms(state, 0) |> should.equal(0)
}

pub fn scope_absent_downgrades_to_none_test() {
  // The response is the whole truth: a response without a scope header
  // downgrades a state that had one.
  let shared =
    rate_limit.update(
      rate_limit.new(),
      response(200, [#("X-RateLimit-Scope", "shared")]),
    )
  let stripped =
    rate_limit.update(shared, response(200, [#("X-RateLimit-Bucket", "x")]))

  stripped.scope |> should.equal(None)
}

pub fn scope_global_rides_along_test() {
  let state =
    rate_limit.update(
      rate_limit.new(),
      response(429, [
        #("Retry-After", "2"),
        #("X-RateLimit-Scope", "global"),
      ]),
    )

  state.scope |> should.equal(Some(rest.ScopeGlobal))
  state.retry_after_ms |> should.equal(Some(2000))
}

// associate

pub fn associate_binds_bucket_test() {
  let key = rate_limit.route_key("GET", "/channels/123456789012345678/messages")
  let routes =
    rate_limit.associate(
      dict.new(),
      key,
      response(200, [
        #("X-RateLimit-Bucket", "bckt-1"),
      ]),
    )

  routes
  |> should.equal(dict.insert(dict.new(), key, error.bucket_id("bckt-1")))
}

pub fn associate_without_bucket_header_is_noop_test() {
  let key = rate_limit.route_key("GET", "/channels/123456789012345678/messages")
  let routes = rate_limit.associate(dict.new(), key, response(200, []))

  routes |> should.equal(dict.new())
}

pub fn associate_rebinds_when_discord_shuffles_test() {
  let key =
    rate_limit.route_key("POST", "/channels/123456789012345678/messages")
  let routes =
    rate_limit.associate(
      dict.new(),
      key,
      response(200, [
        #("X-RateLimit-Bucket", "bckt-old"),
      ]),
    )
  let routes =
    rate_limit.associate(
      routes,
      key,
      response(200, [
        #("X-RateLimit-Bucket", "bckt-new"),
      ]),
    )

  routes
  |> should.equal(dict.insert(dict.new(), key, error.bucket_id("bckt-new")))
}

// the storm: 50 synthetic requests across 3 buckets, no clock, no sleep

const bucket_a = #("GET", "/channels/111111111111111111/messages", "storm-a", 5)

const bucket_b = #("POST", "/guilds/222222222222222222/members", "storm-b", 3)

const bucket_c = #("GET", "/webhooks/333333333333333333", "storm-c", 7)

pub fn storm_across_three_buckets_test() {
  let #(fours, routes) = run_storm(dict.new(), dict.new(), dict.new(), 0, 0)

  // deterministic: with limits 5/3/7 over 50 round-robin steps, a starves
  // twice, b four times, c twice
  fours |> should.equal(8)

  routes
  |> should.equal(
    dict.from_list([
      #("GET /channels/:id/messages", error.bucket_id("storm-a")),
      #("POST /guilds/:id/members", error.bucket_id("storm-b")),
      #("GET /webhooks/:id", error.bucket_id("storm-c")),
    ]),
  )
}

fn run_storm(
  states: dict.Dict(String, rate_limit.BucketState),
  routes: dict.Dict(String, error.BucketId),
  tokens: dict.Dict(String, Int),
  fours: Int,
  step: Int,
) -> #(Int, dict.Dict(String, error.BucketId)) {
  case step >= 50 {
    True -> #(fours, routes)
    False -> {
      let #(method, path, bucket, limit) = case step % 3 {
        0 -> bucket_a
        1 -> bucket_b
        _ -> bucket_c
      }
      let route = rate_limit.route_key(method, path)
      let tokens_now = case dict.get(tokens, bucket) {
        Ok(t) -> t
        Error(_) -> limit
      }
      let #(reply, expected_remaining, expected_wait, tokens_next, fours_next) = case
        tokens_now <= 0
      {
        True -> #(
          response(429, [
            #("X-RateLimit-Limit", int.to_string(limit)),
            #("X-RateLimit-Remaining", "0"),
            #("X-RateLimit-Reset-After", "1.5"),
            #("X-RateLimit-Bucket", bucket),
            #("Retry-After", "2"),
          ]),
          Some(0),
          2000,
          limit,
          fours + 1,
        )
        False -> {
          let remaining = tokens_now - 1
          #(
            response(200, [
              #("X-RateLimit-Limit", int.to_string(limit)),
              #("X-RateLimit-Remaining", int.to_string(remaining)),
              #("X-RateLimit-Reset-After", "1.5"),
              #("X-RateLimit-Bucket", bucket),
            ]),
            Some(remaining),
            case remaining {
              0 -> 1500
              _ -> 0
            },
            remaining,
            fours,
          )
        }
      }

      // caller flow: state lives under the bucket id once one is known,
      // under the masked route key before that
      let identity = case dict.get(routes, route) {
        Ok(id) -> error.bucket_id_to_string(id)
        Error(_) -> route
      }
      let state = case dict.get(states, identity) {
        Ok(existing) -> existing
        Error(_) -> rate_limit.new()
      }
      let state = rate_limit.update(state, reply)
      let routes = rate_limit.associate(routes, route, reply)
      let identity = case dict.get(routes, route) {
        Ok(id) -> error.bucket_id_to_string(id)
        Error(_) -> identity
      }
      let states = dict.insert(states, identity, state)

      // remaining tracks the count going down; wait is positive exactly on
      // an emptied bucket (1500) or a 429 (2000)
      state.remaining |> should.equal(expected_remaining)
      rate_limit.wait_ms(state, 0) |> should.equal(expected_wait)

      run_storm(
        states,
        routes,
        dict.insert(tokens, bucket, tokens_next),
        fours_next,
        step + 1,
      )
    }
  }
}
