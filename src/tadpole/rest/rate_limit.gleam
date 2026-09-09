//// Per-bucket rate-limit state for REST: the numbers responses have
//// reported and the waits they imply. Values come from response headers
//// and 429 bodies only — no hardcoded table, because Discord changes
//// buckets without notice and the headers are the only truth available.
////
//// Pure: no processes, no clock. Time enters as integer arguments; the
//// caller owns the clock and the route -> bucket map (`associate`).
//// Stability: Growing.
////
//// [`tadpole/rest/execute`](execute.html) owns the bookkeeping; this
//// module owns the arithmetic. Nothing here sleeps, sends, or remembers.
////
//// ## When you reach for this
////
//// Directly, almost never — unless you are writing your own executor or
//// a test that wants exact wait math. `BucketState` is a public record
//// on purpose, same status as RestRequest: plain data, nothing here is
//// an invariant worth guarding.
////
//// ## wait_ms: what now_ms means
////
//// `wait_ms(state, now_ms)` answers "how long should the next request
//// on this bucket hold off?". The parameter name misleads everyone
//// once: `now_ms` is NOT a clock reading. It is the time elapsed since
//// the response that last updated this state — `0` immediately after
//// `update`, and whatever the caller's clock says after that. Tadpole
//// never reads a clock; the caller stamps each response and subtracts.
////
//// Priority order: a 429's retry window first (`retry_after_ms` minus
//// elapsed), then a known-empty bucket (`remaining == 0`) counting down
//// `reset_after_ms`, else 0. That final 0 is deliberate: with no
//// headers observed, fire and accept the risk of another 429 —
//// inventing a wait would stall buckets Discord never limited.
////
//// ## Route masking
////
//// `route_key` masks every all-digit path segment of 15+ characters to
//// `:id`, producing "GET /channels/:id/messages". That is a grouping
//// key, not Discord's bucket identity: it folds every channel id into
//// one key, so pre-bucket state mixes traffic across major parameters —
//// a wait learned on channel A gates channel B too. Discord's real
//// per-id bucketing is visible only in the `X-RateLimit-Bucket` header,
//// which is what `associate` binds.
////
//// ## associate: re-keying
////
//// Until a response names a bucket, state lives under the masked route
//// key. `associate` binds route key -> bucket id once
//// `X-RateLimit-Bucket` appears; from that response on, the bucket id is
//// the state key and lookups should prefer it. A later response naming
//// a different bucket simply overwrites the binding — Discord
//// reshuffles buckets sometimes. No bucket header, no change.
////
//// ## Failure modes
////
//// Cannot fail: no I/O, and nothing parses but what the caller already
//// parsed. Degenerate inputs degrade instead — `update` with no parsed
//// headers leaves the state untouched; a half-headered response
//// downgrades the fields it omits to `None` (the response is the whole
//// truth). Only a 429 sets the retry window; a `Retry-After` on any
//// other status is ignored.
////
//// ## See also
////
//// - [`tadpole/rest/execute`](execute.html) — the caller that juggles this state
//// - [`tadpole/rest`](../rest.html) — the header parsing that feeds `update`

import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import tadpole/error.{type BucketId}
import tadpole/rest.{type RateLimitHeaders, type RestResponse}

/// A public record on purpose: states are plain data the caller juggles
/// per bucket, same as RestRequest. Nothing here is an invariant worth
/// guarding.
pub type BucketState {
  BucketState(
    limit: Option(Int),
    remaining: Option(Int),
    reset_after_ms: Option(Float),
    retry_after_ms: Option(Int),
    bucket: Option(BucketId),
  )
}

/// Blank state: nothing observed yet.
pub fn new() -> BucketState {
  BucketState(
    limit: None,
    remaining: None,
    reset_after_ms: None,
    retry_after_ms: None,
    bucket: None,
  )
}

/// Fold one response's rate-limit headers into the state.
///
/// Any header Discord omitted degrades that field to `None`: the response
/// is the whole truth, so a half-headered response downgrades what was
/// known. A response with no parsed rate-limit headers at all (the caller
/// skipped `rest.parse_rate_limit_headers`) leaves the state untouched
/// instead of erasing it.
///
/// Only a 429 sets the retry window: `Retry-After` (seconds, converted to
/// ms) first, then `X-RateLimit-Reset-After`, else `None`. A `Retry-After`
/// on any other status is ignored.
pub fn update(state: BucketState, response: RestResponse) -> BucketState {
  case response.rate_limit_headers {
    None -> state
    Some(headers) ->
      BucketState(
        limit: headers.limit,
        remaining: headers.remaining,
        reset_after_ms: headers.reset_after,
        retry_after_ms: case response.status == 429 {
          True -> retry_window_ms(headers)
          False -> None
        },
        bucket: headers.bucket |> option.map(error.bucket_id),
      )
  }
}

/// 429 windows only. Retry-After is whole seconds per the HTTP spec; a
/// fractional one fails int.parse and falls through to reset_after.
fn retry_window_ms(headers: RateLimitHeaders) -> Option(Int) {
  case headers.retry_after {
    Some(seconds) -> Some(seconds * 1000)
    None ->
      case headers.reset_after {
        Some(seconds) -> Some(float.round(seconds *. 1000.0))
        None -> None
      }
  }
}

/// How long the next request on this bucket should hold off, in ms.
/// 0 means fire now.
///
/// `now_ms` is time elapsed since the response that last updated this
/// state: 0 right after `update`, growing as the caller's clock runs.
/// Tadpole never reads a clock, so the caller stamps each response and
/// does that subtraction itself.
///
/// Priority: a 429's retry window first, then a known-empty bucket
/// (`remaining` 0) counting down `reset_after`, else 0. That final 0 is
/// optimistic — with no headers observed we fire and accept the risk of
/// another 429, because inventing a wait would stall buckets Discord never
/// limited. Windows also anchor when `update` runs, so network latency
/// makes waits slightly longer than strictly needed; that skew errs safe.
pub fn wait_ms(state: BucketState, now_ms: Int) -> Int {
  case state.retry_after_ms {
    Some(window_ms) -> int.max(0, window_ms - now_ms)
    None ->
      case state.remaining, state.reset_after_ms {
        Some(0), Some(seconds) ->
          int.max(0, float.round(seconds *. 1000.0) - now_ms)
        _, _ -> 0
      }
  }
}

/// "<METHOD> <path>" with every all-digit segment of 15+ characters
/// masked to `:id`.
///
/// This is a grouping key, not Discord's bucket identity. Masking folds
/// every channel (or guild, or webhook) id into one key, so pre-bucket
/// state mixes traffic across major parameters — a wait learned on channel
/// A gates channel B too, and a 429 on B can surprise A's state. Discord's
/// real per-id bucketing is only visible in the `X-RateLimit-Bucket`
/// header; `associate` binds it once a response has been seen, and lookups
/// should prefer the bucket id from then on.
///
///     rate_limit.route_key("GET", "/channels/862474250334586890/messages")
///     // -> "GET /channels/:id/messages"
///
pub fn route_key(method: String, path: String) -> String {
  let masked = path |> string.split("/") |> list.map(mask_snowflake)
  method <> " " <> string.join(masked, "/")
}

/// Snowflakes are 17-19 digits today; 15 covers older, shorter ones
/// without touching short numbers like the v10 in the base path.
fn mask_snowflake(segment: String) -> String {
  case string.length(segment) >= 15 && is_digits(segment) {
    True -> ":id"
    False -> segment
  }
}

fn is_digits(segment: String) -> Bool {
  case segment {
    "" -> False
    _ ->
      segment
      |> string.to_graphemes
      |> list.all(fn(grapheme) { string.contains("0123456789", grapheme) })
  }
}

/// Bind a route key to the `X-RateLimit-Bucket` id the response carried.
/// No bucket header, or no parsed headers — the dict comes back unchanged.
///
/// The dict belongs to the caller and stays plain data: key it by
/// `route_key` output, check it before each request, and from the first
/// bound response onward use the bucket id as the state key. A response
/// naming a different bucket than before simply overwrites the binding;
/// Discord reshuffles buckets sometimes.
pub fn associate(
  routes: Dict(String, BucketId),
  key: String,
  response: RestResponse,
) -> Dict(String, BucketId) {
  case response.rate_limit_headers {
    Some(headers) ->
      case headers.bucket {
        Some(value) -> dict.insert(routes, key, error.bucket_id(value))
        None -> routes
      }
    None -> routes
  }
}
