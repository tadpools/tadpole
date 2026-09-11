//// Error rendering: typed errors in, human-readable messages out.
//// Severity decides how much personality the message gets — auth failures
//// get none, ordinary hiccups get one friendly line.
////
//// ## When you reach for this
////
//// Through [`tadpole/guide`](../guide.html) — the guide's bot runner
//// calls `render_error` to log `TadpoleError` values. Directly when you
//// need a severity for programmatic dispatch (`severity_of`).
////
//// ## The severity ladder
////
//// Every variant maps to one of four severities in `severity_of`, and
//// the severity picks the voice: the more severe the failure, the
//// quieter the whimsy, and every rendered body ends with concrete next
//// steps where any exist.
////
//// | Variant(s) | Severity |
//// | --- | --- |
//// | `GatewayConnectFailed`, `HeartbeatAckMissed`, `HeartbeatTimeout`, `RateLimited`, `UnknownEvent` | `Light` — one friendly line; these self-correct |
//// | `ShardingNotSupported`, `GatewayClosedUnexpectedly` (unresumable), `ResumeFailed`, `RestStatus`, `DecodeFailed` | `Actionable` — notes plus a straight Try: list |
//// | `GatewayClosedUnexpectedly` (unresumable → Severe), `MissingToken`, `InvalidTokenFormat`, `IntentsNotPrivileged`, `IdentifyFailed` | `Severe` — zero whimsy, do-this-now steps |
//// | `InternalContractViolation` | `Internal` — tadpole's bug: apology and a report request |
////
//// (`GatewayClosedUnexpectedly` is the one variant that straddles: it
//// is `Actionable` when the session can resume, `Severe` when it
//// cannot.) The token is redacted in every rendered string, and tests
//// assert a planted full token never appears.
////
//// ## See also
////
//// - [`tadpole/error`](../error.html) — the variants being rendered
//// - [`tadpole/guide`](../guide.html) — render_error in a running bot

import gleam/int
import gleam/option.{None, Some}
import gleam/string
import tadpole/error.{
  type TadpoleError, DecodeFailed, GatewayClosedUnexpectedly,
  GatewayConnectFailed, HeartbeatAckMissed, HeartbeatTimeout, IdentifyFailed,
  IntentsNotPrivileged, InternalContractViolation, InvalidTokenFormat,
  MissingToken, RateLimited, RestStatus, ResumeFailed, ShardingNotSupported,
  UnknownEvent, redact_token, route_to_string,
}

/// How serious the error is, controlling how much whimsy the rendered
/// message carries. More severe = quieter voice, concrete next steps.
pub type Severity {
  Light
  Actionable
  Severe
  Internal
}

/// Map an error to its severity. `GatewayClosedUnexpectedly` is the one
/// variant that straddles: `Actionable` when the session can resume,
/// `Severe` when it cannot.
pub fn severity_of(error: TadpoleError) -> Severity {
  case error {
    MissingToken -> Severe
    InvalidTokenFormat(_) -> Severe
    IntentsNotPrivileged(_) -> Severe
    ShardingNotSupported(_) -> Actionable

    GatewayConnectFailed(_, _, _) -> Light
    GatewayClosedUnexpectedly(_, can_resume, _, _) ->
      case can_resume {
        True -> Actionable
        False -> Severe
      }
    HeartbeatAckMissed(_, _) -> Light
    HeartbeatTimeout(_) -> Light
    IdentifyFailed(_) -> Severe
    ResumeFailed(_) -> Actionable

    RestStatus(_, _, _, _) -> Actionable
    RateLimited(_, _, _, _) -> Light

    DecodeFailed(_, _, _, _) -> Actionable
    UnknownEvent(_, _) -> Light

    InternalContractViolation(_, _, _) -> Internal
  }
}

/// Render a `TadpoleError` into a human-readable message. The token is
/// redacted everywhere it could surface; tests assert a planted full
/// token never appears in the output.
pub fn render_error(error: TadpoleError) -> String {
  let #(title, body) = describe(error)
  let prefix = voice_prefix(severity_of(error))

  case body {
    "" -> prefix <> title
    _ -> prefix <> title <> "\n\n" <> body
  }
}

fn voice_prefix(severity: Severity) -> String {
  case severity {
    Light -> "Polly notes: "
    Actionable -> "Polly notes: "
    Severe -> "Polly says: "
    Internal -> "Polly says (this one's on me): "
  }
}

/// The `(title, body)` pair for an error. Body is "" when a title alone
/// suffices. Every body ends with concrete next steps where any exist.
fn describe(error: TadpoleError) -> #(String, String) {
  case error {
    MissingToken -> #(
      "Authentication failed: no bot token was provided.",
      "Your bot token was not provided or is an empty string.\n\n"
        <> "Try:\n"
        <> "  1. Get a bot token from the Discord Developer Portal → Bot → Reset Token\n"
        <> "  2. Load it from an environment variable, never from source code\n"
        <> "  3. If it may have leaked, reset it in the portal now",
    )

    InvalidTokenFormat(got) -> #(
      "Authentication failed: the token format looks wrong.",
      "Discord bot tokens are three dot-separated parts starting with a base64 "
        <> "application ID. Tadpole received: "
        <> redact_token(got)
        <> "\n\nTry:\n"
        <> "  1. Check the token for stray quotes, whitespace, or truncation\n"
        <> "  2. Confirm you copied a *bot* token, not a client secret or user token\n"
        <> "  3. If unsure, reset the token in the portal and copy the new one",
    )

    IntentsNotPrivileged(intent) -> #(
      "Startup refused: "
        <> intent_display(intent)
        <> " is a privileged intent.",
      "The "
        <> intent_display(intent)
        <> " intent requires a toggle in the Developer Portal; requesting it "
        <> "without that toggle disconnects the bot with close code 4014.\n\n"
        <> "Try:\n"
        <> "  1. Open the Developer Portal → Bot → Privileged Gateway Intents\n"
        <> "  2. Enable "
        <> intent_display(intent)
        <> "\n  3. Save, then restart your bot\n"
        <> "Or remove this intent if your bot doesn't need it.",
    )

    ShardingNotSupported(got) -> #(
      "Tadpole's bot layer runs exactly one shard per bot right now.",
      "The config asked for "
        <> int.to_string(got)
        <> " shards. Multi-shard fleets need the identify pacing and "
        <> "/gateway/bot wiring that are not built yet, so tadpole refuses "
        <> "the config instead of connecting a broken fleet.\n\nTry:\n"
        <> "  1. Remove with_shards from your config — one shard is the default\n"
        <> "  2. If your bot genuinely needs several shards (2,500+ guilds), "
        <> "open an issue so multi-shard support gets prioritised",
    )

    GatewayConnectFailed(reason, attempt, next_retry_ms) -> #(
      "Could not connect to the Discord Gateway.",
      "Attempt "
        <> int.to_string(attempt)
        <> " failed: "
        <> error.connect_reason_to_string(reason)
        <> ".\n\nTadpole retries automatically (next attempt in "
        <> int.to_string(next_retry_ms)
        <> "ms).\n"
        <> "If failures persist:\n"
        <> "  1. Check network connectivity and DNS\n"
        <> "  2. Verify your token is valid\n"
        <> "  3. Check https://discordstatus.com for outages",
    )

    GatewayClosedUnexpectedly(code, can_resume, _, _) -> #(
      "The Gateway connection closed unexpectedly.",
      close_code_explanation(code)
        <> resume_note(can_resume)
        <> "\n\nTadpole handles reconnection"
        <> case can_resume {
        True -> " and will attempt a session resume."
        False -> " with a fresh Identify."
      },
    )

    HeartbeatAckMissed(expected, received) -> #(
      "Missed some heartbeat acknowledgments.",
      "Tadpole expected "
        <> int.to_string(expected)
        <> " heartbeat ACKs but received "
        <> int.to_string(received)
        <> ".\n\nThis usually self-corrects. If it repeats:\n"
        <> "  1. Check network stability\n"
        <> "  2. Check for CPU starvation of the BEAM scheduler",
    )

    HeartbeatTimeout(interval_ms) -> #(
      "A heartbeat round-trip timed out.",
      "No heartbeat ACK arrived within "
        <> int.to_string(interval_ms)
        <> "ms. Tadpole will treat the connection as suspect and "
        <> "reconnect if the next heartbeat also fails.",
    )

    IdentifyFailed(reason) -> #(
      "Discord rejected the Identify payload.",
      "Discord refused the bot's Identify: "
        <> reason
        <> "\n\nTry:\n"
        <> "  1. Verify your token is a valid bot token\n"
        <> "  2. Verify your intents are enabled in the portal\n"
        <> "  3. Check the shard configuration is within session limits",
    )

    ResumeFailed(reason) -> #(
      "Session resume failed; Tadpole will re-identify instead.",
      "Resume was refused: "
        <> reason
        <> "\n\nNo action needed — Tadpole falls back to a fresh Identify "
        <> "automatically. Events during the gap were missed; if you cache "
        <> "state, consider a resync.",
    )

    RestStatus(route, status, discord_code, _) -> #(
      "Discord rejected " <> route_to_string(route) <> ".",
      "HTTP "
        <> int.to_string(status)
        <> case discord_code {
        Some(code) -> " (Discord error code " <> int.to_string(code) <> ")"
        None -> ""
      }
        <> "\n\nTry:\n"
        <> "  1. Check the endpoint's required permissions\n"
        <> "  2. Verify IDs are correct (a 404 here usually means the resource "
        <> "is gone or the ID is wrong)\n"
        <> "  3. See https://hexdocs.pm/tadpole/errors.html#"
        <> case discord_code {
        Some(code) -> int.to_string(code)
        None -> int.to_string(status)
      },
    )

    RateLimited(route, retry_after_ms, is_global, _) -> #(
      "The Current slowed us down — Discord asked for a wait.",
      route_to_string(route)
        <> " hit a rate limit; wait "
        <> int.to_string(retry_after_ms)
        <> "ms"
        <> case is_global {
        True -> " (this is a GLOBAL limit — every route is affected)."
        False -> "."
      }
        <> "\n\nTry:\n"
        <> "  1. Nothing — Tadpole queued the request and will send it automatically\n"
        <> "  2. If 429s are frequent, batch with bulk endpoints or add delays\n"
        <> "  3. Never retry immediately; that risks an IP ban",
    )

    DecodeFailed(event, path, expected, got) -> #(
      "A Gateway payload didn't match the expected shape.",
      case event {
        Some(name) -> "Event: " <> name <> "\n"
        None -> ""
      }
        <> "Path: "
        <> path
        <> "\nExpected: "
        <> expected
        <> "\nGot: "
        <> truncate(got, 120)
        <> "\n\nTry:\n"
        <> "  1. Update Tadpole — Discord may have changed this payload\n"
        <> "  2. If you're on the latest version, please report this with the "
        <> "path and expected/got above (no message content needed)",
    )

    UnknownEvent(name, opcode) -> #(
      "Discord sent an event Tadpole doesn't model yet.",
      "Event: "
        <> name
        <> " (opcode "
        <> int.to_string(opcode)
        <> ")\n\nThis is safe — your handlers received it as UnknownEvent and "
        <> "your bot kept running.\n"
        <> "  1. Update Tadpole to the latest version\n"
        <> "  2. If it's still unmodeled, open an issue so we can add it",
    )

    InternalContractViolation(location, details, cause) -> #(
      "Tadpole hit an internal error. This is a bug in Tadpole, not your code.",
      "Location: "
        <> location
        <> "\nDetails: "
        <> details
        <> case cause {
        Some(text) -> "\nCause: " <> text
        None -> ""
      }
        <> "\n\nYour bot may keep running, but please report this:\n"
        <> "  1. Open an issue with the location and details above\n"
        <> "  2. Include your Tadpole version and OTP version\n"
        <> "  3. Redact any tokens — the report should never contain them",
    )
  }
}

fn intent_display(intent: error.IntentName) -> String {
  case intent {
    error.GuildMembersIntent -> "Server Members"
    error.GuildPresencesIntent -> "Presence"
    error.MessageContentIntent -> "Message Content"
  }
}

fn resume_note(can_resume: Bool) -> String {
  case can_resume {
    True -> " The session can be resumed."
    False -> " The session cannot be resumed; a fresh Identify is required."
  }
}

fn close_code_explanation(code: Int) -> String {
  case code {
    1000 -> "Discord closed the connection normally (code 1000)."
    1001 ->
      "Discord is going away — the connection is being replaced (code 1001)."
    1006 ->
      "The connection was lost without a close frame (code 1006) — usually a network drop."
    4000 -> "Discord reported an unknown error (code 4000)."
    4001 -> "Tadpole sent an opcode Discord didn't expect (code 4001)."
    4002 -> "A payload arrived malformed (code 4002)."
    4003 -> "The session was not authenticated before sending (code 4003)."
    4004 ->
      "Authentication failed — the token is invalid or was reset (code 4004)."
    4005 -> "The session was already authenticated (code 4005)."
    4007 ->
      "The sequence number was invalid (code 4007) — the session is stale."
    4008 -> "Sending rate limited (code 4008) — payloads were sent too fast."
    4009 -> "The session timed out (code 4009)."
    4010 -> "The requested shard is invalid (code 4010)."
    4011 -> "Sharding is required for this bot (code 4011)."
    4012 -> "An invalid API version was requested (code 4012)."
    4013 -> "The intents value is invalid (code 4013)."
    4014 ->
      "The intents include privileged values not enabled in the portal (code 4014)."
    other ->
      "Discord closed the connection with code " <> int.to_string(other) <> "."
  }
}

fn truncate(text: String, max: Int) -> String {
  case string.length(text) > max {
    True -> string.slice(text, 0, max) <> "…"
    False -> text
  }
}
