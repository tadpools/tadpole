//// Properties for rate-limit arithmetic: waits are never negative,
//// never grow as elapsed time runs forward, and the 429 retry window
//// outranks the empty-bucket reset window. route_key masking is checked
//// against the snowflake shapes Discord actually sends. See
//// test/tadpole/support/property for the harness.

import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import tadpole/rest.{RateLimitHeaders, RestResponse}
import tadpole/rest/rate_limit
import tadpole/support/property.{type Gen}

fn seconds() -> Gen(Float) {
  property.map(property.int_in(0, 60), fn(tenths) {
    case float.divide(int.to_float(tenths), 10.0) {
      Ok(f) -> f
      Error(_) -> 0.0
    }
  })
}

fn headers(
  limit: Option(Int),
  remaining: Option(Int),
  reset_after: Option(Float),
  retry_after: Option(Int),
) -> rest.RateLimitHeaders {
  RateLimitHeaders(
    limit: limit,
    remaining: remaining,
    reset: None,
    reset_after: reset_after,
    bucket: Some("test-bucket"),
    retry_after: retry_after,
    is_global: False,
    scope: None,
  )
}

fn response(status: Int, rl: rest.RateLimitHeaders) -> rest.RestResponse {
  RestResponse(
    status: status,
    headers: [],
    body: "",
    rate_limit_headers: Some(rl),
  )
}

fn elapsed() -> Gen(Int) {
  property.int_in(0, 120_000)
}

pub fn wait_is_never_negative_test() {
  // Every combination of status and fully-populated headers: wait_ms
  // must never tell the caller to travel back in time.
  property.check(
    "wait_ms is never negative",
    fn(pair) {
      let #(status, _) = pair
      "status " <> int.to_string(status)
    },
    property.map2(
      property.one_of([429, 200, 204, 403]),
      elapsed(),
      fn(status, e) { #(status, e) },
    ),
    fn(pair) {
      let #(status, e) = pair
      let state =
        rate_limit.update(
          rate_limit.new(),
          response(status, headers(Some(10), Some(0), Some(2.5), Some(5))),
        )
      rate_limit.wait_ms(state, e) >= 0
    },
  )
}

pub fn wait_never_grows_with_elapsed_time_test() {
  // Holding the state fixed and moving the clock forward can only
  // shrink (or hold) the wait.
  property.check(
    "wait_ms is monotone non-increasing in elapsed time",
    fn(pair) {
      let #(window, e) = pair
      int.to_string(window) <> "ms elapsed " <> int.to_string(e)
    },
    property.map2(property.int_in(0, 60_000), elapsed(), fn(w, e) { #(w, e) }),
    fn(pair) {
      let #(window, e) = pair
      let state =
        rate_limit.update(
          rate_limit.new(),
          response(429, headers(None, None, None, Some(window))),
        )
      let earlier = rate_limit.wait_ms(state, e)
      let later = rate_limit.wait_ms(state, e + 1)
      later <= earlier
    },
  )
}

pub fn retry_window_outranks_reset_window_test() {
  // When a 429 sets a retry window, that window rules even if the
  // bucket also reports remaining == 0 with its own reset_after.
  property.check(
    "429 retry window outranks the empty-bucket reset window",
    fn(triple) {
      let #(#(retry, reset), _) = triple
      int.to_string(retry) <> "/" <> float.to_string(reset) <> "s"
    },
    property.map2(
      property.map2(property.int_in(1, 30), seconds(), fn(r, s) { #(r, s) }),
      elapsed(),
      fn(rs, e) { #(rs, e) },
    ),
    fn(pair) {
      let #(#(retry, reset), e) = pair
      let state =
        rate_limit.update(
          rate_limit.new(),
          response(429, headers(Some(10), Some(0), Some(reset), Some(retry))),
        )
      rate_limit.wait_ms(state, e) == int.max(0, retry * 1000 - e)
    },
  )
}

pub fn empty_bucket_waits_out_reset_after_test() {
  // remaining == 0 without a 429: the reset_after window rules.
  property.check(
    "remaining == 0 counts down reset_after",
    fn(pair) {
      let #(reset, _) = pair
      float.to_string(reset) <> "s"
    },
    property.map2(seconds(), elapsed(), fn(s, e) { #(s, e) }),
    fn(pair) {
      let #(reset, e) = pair
      let state =
        rate_limit.update(
          rate_limit.new(),
          response(200, headers(Some(10), Some(0), Some(reset), None)),
        )
      rate_limit.wait_ms(state, e)
      == int.max(0, float.round(reset *. 1000.0) - e)
    },
  )
}

pub fn unobserved_bucket_waits_zero_test() {
  // No retry window and remaining > 0: fire now. That 0 is the
  // documented optimistic default, so lock it.
  property.check(
    "no window and remaining > 0 means fire now",
    fn(pair) {
      let #(remaining, _) = pair
      "remaining " <> int.to_string(remaining)
    },
    property.map2(property.int_in(1, 50), elapsed(), fn(r, e) { #(r, e) }),
    fn(pair) {
      let #(remaining, e) = pair
      let state =
        rate_limit.update(
          rate_limit.new(),
          response(200, headers(Some(10), Some(remaining), Some(30.0), None)),
        )
      rate_limit.wait_ms(state, e) == 0
    },
  )
}

pub fn update_without_headers_leaves_state_untouched_test() {
  property.check(
    "a headerless response never erases known state",
    fn(pair) {
      let #(retry, _) = pair
      int.to_string(retry) <> "ms window"
    },
    property.map2(property.int_in(1, 30_000), elapsed(), fn(w, e) { #(w, e) }),
    fn(pair) {
      let #(retry, e) = pair
      let limited =
        rate_limit.update(
          rate_limit.new(),
          response(429, headers(Some(5), Some(0), Some(2.0), Some(retry))),
        )
      let headerless =
        RestResponse(
          status: 200,
          headers: [],
          body: "",
          rate_limit_headers: None,
        )
      let after = rate_limit.update(limited, headerless)
      rate_limit.wait_ms(after, e) == rate_limit.wait_ms(limited, e)
    },
  )
}

pub fn route_key_masks_every_long_digit_segment_test() {
  // Any all-digit segment of 15+ characters is masked, whatever it is:
  // exactly as many ":id"s as long digit segments, and no long digit
  // segment survives.
  property.check(
    "route_key masks digit segments of 15+ chars",
    fn(input) {
      let #(path, longs) = input
      int.to_string(longs) <> " long segments in " <> path
    },
    long_digit_path(),
    fn(input) {
      let #(path, long_count) = input
      let masked = rate_limit.route_key("GET", path)
      let id_marks = case string.split(masked, ":id") {
        [_only] -> 0
        parts -> list.length(parts) - 1
      }
      id_marks == long_count
      && list.all(string.split(masked, "/"), fn(segment) {
        case string.length(segment) >= 15 {
          True -> !all_digits(segment)
          False -> True
        }
      })
    },
  )
}

pub fn route_key_keeps_short_segments_test() {
  // Short segments (v10, 3, etc.) survive unmasked.
  property.check(
    "route_key keeps short segments intact",
    fn(path) { path },
    mixed_path(),
    fn(path) { rate_limit.route_key("GET", path) == "GET " <> path },
  )
}

pub fn route_key_masking_is_idempotent_test() {
  // Masking an already-masked path changes nothing: the same route
  // always folds into the same key. The method is stripped first,
  // because route_key output is "METHOD path" and only the path is a
  // route_key input.
  property.check(
    "route_key masking is idempotent",
    fn(input) {
      let #(path, _) = input
      path
    },
    long_digit_path(),
    fn(input) {
      let #(path, _) = input
      let once = rate_limit.route_key("GET", path)
      let assert Ok(once_path) = rest_route_path(once)
      rate_limit.route_key("GET", once_path) == once
    },
  )
}

// "GET /channels/:id" -> Ok("/channels/:id"); anything else is a test
// bug, because route_key always emits "METHOD path".
fn rest_route_path(key: String) -> Result(String, Nil) {
  case string.split_once(key, " ") {
    Ok(#(_method, path)) -> Ok(path)
    Error(_) -> Error(Nil)
  }
}

fn long_digit_path() -> Gen(#(String, Int)) {
  property.map2(
    property.list_of(property.digit_string(15, 19), 1, 3),
    property.list_of(short_segment(), 0, 2),
    fn(longs, shorts) {
      let segments = list.append(longs, shorts)
      #(segments, list.length(longs))
    },
  )
  |> property.map(fn(segments_and_count) {
    let #(segments, long_count) = segments_and_count
    #("/" <> string.join(segments, "/"), long_count)
  })
}

fn mixed_path() -> Gen(String) {
  property.map(property.list_of(short_segment(), 1, 4), fn(segments) {
    "/" <> string.join(segments, "/")
  })
}

fn short_segment() -> Gen(String) {
  property.one_of(["v10", "channels", "messages", "guilds", "3", "reactions"])
}

fn all_digits(segment: String) -> Bool {
  case segment {
    "" -> False
    _ ->
      segment
      |> string.to_graphemes
      |> list.all(fn(grapheme) { string.contains("0123456789", grapheme) })
  }
}
