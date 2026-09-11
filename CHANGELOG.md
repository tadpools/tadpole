# Changelog

Versions are calendar-based (YYYY.MILESTONE.PATCH). Before the first
publish there are no compatibility promises; the tests and this changelog
are the contract.

## 2026.3.0 - unreleased

Hardening and docs alignment: places where the docs said something the
library did not do yet.

- gateway frame parsing is hardened against hostile input. Payloads
  that are not a decodable envelope (wrong op types, arrays, scalars,
  huge or unicode event names, deep nesting, extra fields) degrade to
  a Result and never crash a connection. Valid JSON carrying no op is
  now `FrameMissingOpcode`, distinct from `FrameNotJson` — the docs
  promised two failure modes; both are real now.
- rate limit responses carry `X-RateLimit-Scope` as a typed value
  (user, shared, or global) on the parsed headers and on bucket
  state. Waits ignore scope; an unknown scope degrades to None.
- `RateLimitHeaders.reset` is a float now: the docs' reset is an epoch
  timestamp that may carry a fractional part, and integer parsing
  silently dropped the whole field on those responses. Both whole and
  fractional forms parse (the same tolerant parse covers
  `X-RateLimit-Reset-After`). This is the milestone's one breaking
  field type.
- the first heartbeat on a fresh connection waits
  `heartbeat_interval * jitter` per the docs' thundering-herd rule.
  The math is a pure, clamped function in tadpole/gateway
  (`first_heartbeat_delay_ms`); the shard draws the random value.
- the gateway opcode table matches the docs row for row, including
  the send-only opcodes 31 (Request Soundboard Sounds) and 43
  (Request Channel Info). Unknown opcodes remain data the shard
  ignores.
- intent flags are a sum type now, not bare integer constants.
  `enable`, `disable`, and `has` take a variant (`Guilds`,
  `MessageContent`) instead of an `Int`; a typo'd intent is a
  compile error, not a silent wrong-event-family bug. `intent_name`
  is total on the variant. Wire conversion (`to_int`/`from_int`)
  is unchanged. This is the milestone's second breaking change
  (after the float reset field). (#28)
- snowflake property fuzzing: the seeded harness generates random
  valid timestamps, constructs snowflakes, and asserts roundtrip
  fidelity plus monotonic ordering. ~20 deterministic cases, no
  external property-testing dependency. (#29)

## 2026.2.0 - first-swim (published 2026-09-10)

The first vertical slice: a bot can connect to the gateway, receive
events, and make REST calls. Tests run offline against fixtures, a
seeded property harness, and an env-gated live gate (TADPOLE_TOKEN set
runs the publish gate from CONTRIBUTING; unset, it skips). Published
after the live gate passed twice over: REST authentication and a typed
READY over a real gateway connection, plus a live forced-reconnect
resume verified end to end.

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
- frame parsing accepts Discord's envelope in both shapes it sends:
  fields absent or null. Found live: HELLO's "t": null, "s": null
  failed the old sentinel parse, which left a real connection deaf.
- reconnects can actually resume. Closes on the resume paths sent
  1001, which Discord's docs name as session-invalidating, so every
  reconnect silently degraded to a fresh identify; those paths now
  send 4900 (keep the session) and decide the resume upfront instead
  of trusting whatever code echoes back. Zombie kills attempt the
  resume too, per the docs' zombie rule. The close ladder follows the
  docs' table exactly: 4003 reconnects fresh, 4004 and 4010-4014 stop
  instead of backing off forever (tadpole/gateway/transport,
  tadpole/gateway/shard).
- resume reconnects dial the gateway URL READY names
  (resume_gateway_url) instead of re-dialing the configured one,
  carrying the original connection's query parameters; without a
  captured URL the configured one keeps working
  (tadpole/gateway/shard).
- intent names follow the current gateway docs: guild_bans is now
  guild_moderation and guild_emojis_and_stickers is now
  guild_expressions, with the bit values unchanged; the polls intents
  exist at all now, since GUILD_MESSAGE_POLLS and
  DIRECT_MESSAGE_POLLS could not be enabled before (tadpole/intent).
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
- the User-Agent Discord requires, `DiscordBot ($url, $version)`, sent
  on REST requests and the gateway websocket handshake from one shared
  source (tadpole/user_agent). An invalid user agent risks a Cloudflare
  block before the request reaches the API.
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
