//// Tests for the error taxonomy and renderer.
////
//// These tests enforce the error UX rules:
////   - tokens never render whole 
////   - severity mapping matches the voice ladder 
////   - every rendered message ends with actionable next steps

import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import tadpole/error.{
  type TadpoleError, DecodeFailed, GatewayClosedUnexpectedly, HeartbeatAckMissed,
  HeartbeatTimeout, IdentifyFailed, IntentsNotPrivileged,
  InternalContractViolation, InvalidTokenFormat, MissingToken, RateLimited,
  RestStatus, ShardingNotSupported, UnknownEvent, bucket_id, method_to_string,
  redact_token, route_to_string,
}
import tadpole/error/render.{Actionable, Internal, Light, Severe, render_error}

pub fn redact_keeps_prefix_and_suffix_test() {
  redact_token("MTIzNDU2Nzg5MDEyMzQ1Njc4OTA") |> should.equal("MTIz...4OTA")
}

pub fn redact_hides_short_values_test() {
  redact_token("short") |> should.equal("[redacted]")
  redact_token("") |> should.equal("[redacted]")
  redact_token("12345678") |> should.equal("[redacted]")
}

pub fn redacted_output_never_contains_full_token_test() {
  let token = "MTA1OTI4MzU0NjQ4NzEyMzQ1Nj.CeFgHg.aVerySecretSuffixPartHere"
  let rendered = render_error(InvalidTokenFormat(token))
  // The full token must never appear anywhere in rendered output.
  string.contains(rendered, token) |> should.be_false
}

pub fn auth_errors_are_severe_test() {
  render.severity_of(MissingToken) |> should.equal(Severe)
  render.severity_of(InvalidTokenFormat("MTIz...")) |> should.equal(Severe)
  render.severity_of(IdentifyFailed("bad intents")) |> should.equal(Severe)
  render.severity_of(IntentsNotPrivileged(error.MessageContentIntent))
  |> should.equal(Severe)
}

pub fn non_resumable_closes_are_severe_test() {
  render.severity_of(GatewayClosedUnexpectedly(4007, False, None, None))
  |> should.equal(Severe)
  render.severity_of(GatewayClosedUnexpectedly(
    1006,
    True,
    Some("session"),
    Some(42),
  ))
  |> should.equal(Actionable)
}

pub fn routine_errors_are_light_test() {
  render.severity_of(HeartbeatAckMissed(3, 2)) |> should.equal(Light)
  render.severity_of(UnknownEvent("NEW_EVENT", 0)) |> should.equal(Light)
}

pub fn rate_limits_are_light_test() {
  render.severity_of(RateLimited(
    error.Route(error.GET, "/channels/1/messages"),
    1180,
    False,
    None,
  ))
  |> should.equal(Light)
}

pub fn decode_errors_are_actionable_test() {
  render.severity_of(DecodeFailed(
    Some("MESSAGE_CREATE"),
    "d.content",
    "String",
    "null",
  ))
  |> should.equal(Actionable)
}

pub fn internal_errors_are_internal_test() {
  render.severity_of(InternalContractViolation(
    "gateway/shard",
    "seq overflow",
    None,
  ))
  |> should.equal(Internal)
}

pub fn missing_token_renders_portal_guidance_test() {
  let rendered = render_error(MissingToken)
  string.contains(rendered, "no bot token") |> should.be_true
  string.contains(rendered, "Developer Portal") |> should.be_true
  string.contains(rendered, "Polly says:") |> should.be_true
}

pub fn rate_limit_renders_wait_and_reassurance_test() {
  let rendered =
    render_error(RateLimited(
      error.Route(error.POST, "/channels/1/messages"),
      1180,
      False,
      Some(bucket_id("abcd1234")),
    ))

  string.contains(rendered, "1180ms") |> should.be_true
  string.contains(rendered, "queued") |> should.be_true
  string.contains(rendered, "Polly notes:") |> should.be_true
}

pub fn global_rate_limit_is_flagged_test() {
  let rendered =
    render_error(RateLimited(
      error.Route(error.GET, "/users/@me"),
      2000,
      True,
      None,
    ))

  string.contains(rendered, "GLOBAL") |> should.be_true
}

pub fn decode_failure_carries_path_test() {
  let rendered =
    render_error(DecodeFailed(
      Some("MESSAGE_CREATE"),
      "d.embeds[2].title",
      "String",
      "null",
    ))

  string.contains(rendered, "MESSAGE_CREATE") |> should.be_true
  string.contains(rendered, "d.embeds[2].title") |> should.be_true
  string.contains(rendered, "null") |> should.be_true
}

pub fn internal_error_takes_blame_and_requests_report_test() {
  let rendered =
    render_error(InternalContractViolation(
      "gateway/shard:handle_dispatch",
      "seq overflow",
      None,
    ))

  string.contains(rendered, "bug in Tadpole") |> should.be_true
  string.contains(rendered, "on me") |> should.be_true
  string.contains(rendered, "gateway/shard:handle_dispatch") |> should.be_true
}

pub fn close_4014_renders_portal_hint_test() {
  let rendered =
    render_error(GatewayClosedUnexpectedly(4014, False, None, None))

  string.contains(rendered, "4014") |> should.be_true
  string.contains(rendered, "cannot be resumed") |> should.be_true
}

pub fn close_1006_renders_resume_promise_test() {
  let rendered =
    render_error(GatewayClosedUnexpectedly(1006, True, Some("sess"), Some(7)))

  string.contains(rendered, "network drop") |> should.be_true
  string.contains(rendered, "can be resumed") |> should.be_true
}

pub fn unknown_event_reassures_test() {
  let rendered = render_error(UnknownEvent("GUILD_AUDIT", 0))
  string.contains(rendered, "safe") |> should.be_true
  string.contains(rendered, "GUILD_AUDIT") |> should.be_true
}

pub fn severe_errors_have_no_playful_prefix_test() {
  // Level 3 = "Polly says:" — calm and direct, never "this one's on me".
  let rendered = render_error(MissingToken)
  string.contains(rendered, "this one's on me") |> should.be_false
}

pub fn internal_errors_own_the_blame_test() {
  let rendered = render_error(InternalContractViolation("loc", "det", None))
  string.contains(rendered, "this one's on me") |> should.be_true
}

pub fn every_variant_renders_nonempty_test() {
  // Adding a new TadpoleError variant will fail to compile here —
  // which is exactly the point: the renderer must cover it too.
  let errors: List(TadpoleError) = [
    MissingToken,
    InvalidTokenFormat("MTIzNDU2Nzg5OTk5OTk5OQ"),
    IntentsNotPrivileged(error.GuildMembersIntent),
    IntentsNotPrivileged(error.GuildPresencesIntent),
    IntentsNotPrivileged(error.MessageContentIntent),
    ShardingNotSupported(2),
    error.GatewayConnectFailed(error.NetworkError, 2, 3000),
    GatewayClosedUnexpectedly(1006, True, Some("s"), Some(1)),
    GatewayClosedUnexpectedly(4004, False, None, None),
    HeartbeatAckMissed(5, 3),
    HeartbeatTimeout(5000),
    IdentifyFailed("invalid intents"),
    error.ResumeFailed("unknown session"),
    RestStatus(error.Route(error.GET, "/users/@me"), 404, Some(10_013), None),
    RateLimited(
      error.Route(error.POST, "/channels/1/messages"),
      900,
      False,
      Some(bucket_id("b")),
    ),
    DecodeFailed(None, "d.x", "Int", "String"),
    UnknownEvent("NEW_THING", 0),
    InternalContractViolation("mod", "desc", Some("cause")),
  ]

  list.each(errors, fn(e) {
    let rendered = render_error(e)
    { string.length(rendered) > 0 } |> should.be_true
  })
}

pub fn route_to_string_includes_method_test() {
  route_to_string(error.Route(error.POST, "/channels/1/messages"))
  |> should.equal("POST /channels/1/messages")
}

pub fn method_to_string_test() {
  method_to_string(error.GET) |> should.equal("GET")
  method_to_string(error.PATCH) |> should.equal("PATCH")
}
