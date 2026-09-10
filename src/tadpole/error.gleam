//// Tadpole's error type. Variants carry structured context — route,
//// status, retry-after, decode path — so callers match on them instead
//// of parsing strings; error/render.gleam turns them into human-readable
//// messages, with the token redacted everywhere it could surface.
////
//// ## The taxonomy, grouped by subsystem
////
//// Config (before anything connects — `tadpole.validate`,
//// `bot.start`/`run`):
////
//// - `MissingToken`, `InvalidTokenFormat(got)` — empty or malformed
////   token; `got` is redacted when rendered.
//// - `IntentsNotPrivileged(intent)` — the one named intent needs a
////   Developer Portal toggle.
//// - `ShardingNotSupported(got)` — this milestone runs one shard.
////
//// Gateway (connection lifecycle and protocol):
////
//// - `GatewayConnectFailed(reason, attempt, next_retry_ms)` — one
////   connect attempt failed; the shard retries on its own. `reason` is
////   a `ConnectReason` (below).
//// - `GatewayClosedUnexpectedly(close_code, can_resume, session_id, sequence)`
////   — a live connection closed; the fields say whether the session can
////   resume.
//// - `HeartbeatAckMissed` / `HeartbeatTimeout` — the zombie detectors:
////   ACKs missing, round-trip overdue.
//// - `IdentifyFailed` / `ResumeFailed` — Discord refused the handshake
////   step; the reason is Discord's.
////
//// REST:
////
//// - `RestStatus(route, status, discord_code, body)` — any non-2xx.
////   Status 0 is the transport-failure convention: no HTTP response
////   happened (tadpole/rest/execute explains why no separate variant).
//// - `RateLimited(route, retry_after_ms, is_global, bucket)` — 429s
////   outlasted the retries.
////
//// Decode:
////
//// - `DecodeFailed(event, path, expected, got)` — a payload stopped
////   matching its decoder; `path` is the JSON path, `got` truncated.
//// - `UnknownEvent(event_name, opcode)` — reserved for unmodeled
////   events; nothing raises it today, the typed event layer decodes
////   them to `Unknown` data instead.
////
//// Internal:
////
//// - `InternalContractViolation(location, details, cause)` — a tadpole
////   bug found at runtime. Not your code's fault; the renderer asks for
////   a report.
////
//// ## Route and BucketId
////
//// `Route(method, path)` identifies the REST call in errors — printed
//// as `POST /channels/123/messages` by `route_to_string`.
//// `BucketId` wraps Discord's `X-RateLimit-Bucket` string, the identity
//// rate-limit state is keyed by once a response names it; both are
//// opaque so error payloads cannot be silently reshaped.
//// `ConnectReason` names why a gateway connect failed — from
//// `InvalidToken` to `SessionStartLimited` to `NetworkError` — with
//// `Other(String)` catching anything new.
////
//// ## Failure modes
////
//// Pure data and total functions — this module cannot fail.
//// `redact_token` keeps the first 4 and last 4 characters, `[redacted]`
//// under 9. What the variants mean is above; the renderer is
//// [`tadpole/error/render`](error/render.html).
////
//// ## See also
////
//// - [`tadpole/error/render`](error/render.html) — every variant to text
//// - [`tadpole/guide`](guide.html) — matching `RateLimited` for control flow

import gleam/option.{type Option}
import gleam/string

pub type TadpoleError {
  MissingToken
  InvalidTokenFormat(got: String)
  IntentsNotPrivileged(intent: IntentName)
  /// bot.start runs exactly one shard this milestone; a config asking for
  /// more is refused before any connection is attempted.
  ShardingNotSupported(got: Int)

  GatewayConnectFailed(reason: ConnectReason, attempt: Int, next_retry_ms: Int)
  GatewayClosedUnexpectedly(
    close_code: Int,
    can_resume: Bool,
    session_id: Option(String),
    sequence: Option(Int),
  )
  HeartbeatAckMissed(expected_acks: Int, received_acks: Int)
  HeartbeatTimeout(interval_ms: Int)
  IdentifyFailed(reason: String)
  ResumeFailed(reason: String)

  RestStatus(
    route: Route,
    status: Int,
    discord_code: Option(Int),
    body: Option(String),
  )
  RateLimited(
    route: Route,
    retry_after_ms: Int,
    is_global: Bool,
    bucket: Option(BucketId),
  )

  DecodeFailed(
    event: Option(String),
    path: String,
    expected: String,
    got: String,
  )
  UnknownEvent(event_name: String, opcode: Int)

  InternalContractViolation(
    location: String,
    details: String,
    cause: Option(String),
  )
}

pub type IntentName {
  GuildMembersIntent
  GuildPresencesIntent
  MessageContentIntent
}

pub opaque type BucketId {
  BucketId(String)
}

pub fn bucket_id(value: String) -> BucketId {
  BucketId(value)
}

pub fn bucket_id_to_string(bucket: BucketId) -> String {
  let BucketId(value) = bucket
  value
}

pub type Route {
  Route(method: HttpMethod, path: String)
}

pub fn route_to_string(route: Route) -> String {
  let Route(method, path) = route
  method_to_string(method) <> " " <> path
}

pub type HttpMethod {
  GET
  POST
  PUT
  DELETE
  PATCH
  HEAD
  OPTIONS
}

pub fn method_to_string(method: HttpMethod) -> String {
  case method {
    GET -> "GET"
    POST -> "POST"
    PUT -> "PUT"
    DELETE -> "DELETE"
    PATCH -> "PATCH"
    HEAD -> "HEAD"
    OPTIONS -> "OPTIONS"
  }
}

pub type ConnectReason {
  InvalidToken
  BadRequest
  Unauthorized
  Forbidden
  NotFound
  UnsupportedVersion
  SessionStartLimited
  NetworkError
  TlsError
  ServiceUnavailable
  Other(String)
}

pub fn connect_reason_to_string(reason: ConnectReason) -> String {
  case reason {
    InvalidToken -> "invalid token"
    BadRequest -> "bad request"
    Unauthorized -> "unauthorized"
    Forbidden -> "forbidden"
    NotFound -> "not found"
    UnsupportedVersion -> "unsupported gateway version"
    SessionStartLimited -> "session start limit exceeded"
    NetworkError -> "network error"
    TlsError -> "TLS error"
    ServiceUnavailable -> "service unavailable"
    Other(text) -> text
  }
}

/// First 4 and last 4 chars kept, everything between hidden. Short values
/// become [redacted]. Tests assert the full token never renders.
pub fn redact_token(token: String) -> String {
  let len = string.length(token)
  case len <= 8 {
    True -> "[redacted]"
    False ->
      string.slice(token, 0, 4) <> "..." <> string.slice(token, len - 4, 4)
  }
}
