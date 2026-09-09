# Changelog

Versions are calendar-based (YYYY.MILESTONE.PATCH). Before the first
publish there are no compatibility promises; the tests and this changelog
are the contract.

## 2026.2.0 - first-swim (unreleased, pending live check)

The first vertical slice: a bot can connect to the gateway, receive
events, and make REST calls. All tests run against recorded fixtures.
Not on Hex until the live check
in CONTRIBUTING.md passes (one real gateway roundtrip plus one real
REST call), and it has not run yet.

- model objects and decoders: user, message (full form plus the partial
  MESSAGE_UPDATE form), guild with its unavailable form, channel, and
  the shared decode plumbing that reports where a payload stopped
  matching (tadpole/model).
- REST execution: requests run through an injected transport (gleam_httpc
  ships as the default) with 429 retries, per-session
  rate-limit bookkeeping, and a shared status-0 convention for "no HTTP
  response happened" (tadpole/rest/execute).
- REST endpoint bindings: GET /users/@me, send a message, reply
  (tadpole/rest/endpoints).
- gateway transport: stratus behind an opaque connection handle; stratus
  types never cross into protocol code (tadpole/gateway/transport).
- the shard actor: HELLO, heartbeats on Discord's interval with
  zombie detection, identify or resume from a stored session, close-code
  decisions, reconnect with backoff, lifecycle notices
  (tadpole/gateway/shard).
- typed events: Ready, MessageCreate, MessageUpdate, MessageDelete,
  Resumed, GuildCreate, GuildDelete, and Unknown as the catch-all for
  anything not modeled (tadpole/gateway/events).
- identify pacing defaults for future shard fleets, with max_concurrency
  from GET /gateway/bot left for a later milestone
  (tadpole/gateway/identify_gate).
- the beginner bot runner: start, run, send_message, reply, stop. One
  config, one handler, one shard; events dispatch sequentially in
  arrival order (tadpole/bot).
- the echo bot example (dev/echo_bot.gleam), a gateway smoke run
  (dev/smoke_gw.gleam), and live checks for the publish gate
  (dev/live_checks.gleam, scripts/run-live-tests.ps1).
- one new error variant: `ShardingNotSupported(got)`. bot.start runs
  exactly one shard and refuses a config asking for more before anything
  connects. Severity: Actionable; rendered and tested per the
  CONTRIBUTING rules.

## Unreleased

- Initial protocol layer: snowflake and domain ID types, intent bitfield,
  typed error taxonomy with renderer, gateway opcodes and frame
  parse/build, shard close-code and reconnect decisions, heartbeat zombie
  detection, event dispatch table, REST request builders and rate-limit
  header parsing, config validation.

(The above shipped as part of 2026.2.0. The section is kept for the next
round of work.)
