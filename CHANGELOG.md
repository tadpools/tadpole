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
- identify pacing's docs said the function returns a delay between two
  IDENTIFYs, and pointed readers at `identify_delay_ms`, which does not
  exist. It returns the time the whole fleet takes to come up, which the
  docs now say (tadpole/gateway/identify_gate).
- reconnect backoff caps the doubling instead of raising the power
  first. Returned milliseconds are unchanged for every input, but the
  old version multiplied out the full exponent before discarding it,
  one bignum multiply per attempt, on the shard actor's own process
  (159s to answer 60000 at 1,000,000 attempts). The shard only clears
  its attempt counter on HELLO, so that count grows while the gateway
  stays unreachable (tadpole/gateway). (#34)
- REST requests can carry query parameters. `RestRequest` grows a `query`
  field and `rest.with_query` adds one, kept out of `path` on purpose:
  Discord buckets by route and the query string is not part of the route,
  so the rate-limit key still comes from `path` alone and reads that
  differ only in `limit` share a bucket. Names and values are
  percent-encoded when the request is built (tadpole/rest).
- `endpoints.get_messages` reads a channel's history, one page at a time.
  `MessageQuery` is a sum type (`Latest`, `Before`, `After`, `Around`)
  because Discord's before/after/around are mutually exclusive, so
  sending two is not representable rather than a 400 waiting to happen.
  `MessagePage` carries the messages newest-first as Discord sends them,
  plus `oldest`, the id the next `Before` page needs. `limit` is clamped
  to the documented 1-100 rather than forwarded, since out of range is a
  400. A bot without Read Message History gets a 200 and an empty page,
  not a 403, which the docs now say out loud (tadpole/rest/endpoints).
- `get_channel`, `get_message` and `get_messages` on `tadpole/bot`, which
  brings the wrapper level up to what `endpoints` already had. They go
  over the bot's own transport like every other helper there. Reaching
  for `endpoints.get_channel(bot.rest, id)` instead silently built a
  fresh httpc transport and ignored the bot's, so a Bot built with an
  injected transport would hit the real network for that one call and
  not for the others.
- `decode.from_json` no longer guesses whether a payload is a gateway
  envelope. It decoded a bare object, and if the payload happened to
  carry a top-level `d` key it treated that key as a wrapper and decoded
  the value inside it. No modelled Discord object sends one, so nothing
  live was affected, but a REST body is whatever Discord sent: one with a
  `d` field would have handed the caller a different object with no
  error, and a message that failed to decode degrades to `Unknown` in the
  shard, so the wrong answer looks exactly like the right one. The gateway
  path, which is the one that knows it has an envelope, now says so
  through a new `decode.from_frame`. Breaking for anyone passing a frame
  to a model's `from_json`, which is the call the old heuristic encouraged
  (#37).
- messages carry their reactions. Discord sends `reactions` on every
  message and `model/message` was dropping the field, so answering "who
  reacted" cost a REST call for data that had already arrived. `Message`
  now has `reactions: List(Reaction)`, and `model/emoji` gained the two
  shapes that arrive rather than the one that is sent: `PartialEmoji`
  (a null `id` for a standard emoji, and a null `name`, which the docs
  scope to reaction objects, for a custom emoji since deleted from its
  guild) and `Reaction` (count, the normal/burst split flattened out of
  `count_details`, `me`, `me_burst`, `burst_colors`). `emoji.to_request`
  turns a read emoji back into one you can send, so reacting with what
  you just read is one call. Empty is the normal case, and a payload
  with no `reactions` key decodes to an empty list rather than failing.
  Adding a field to a public record is breaking only for code that
  pattern matches it exhaustively, and no pre-publish release promises
  anything between versions.
- typing indicators: `endpoints.set_typing` is the bare route, and
  `bot.with_typing(channel, work)` is the version worth using. Discord's
  indicator expires after 10 seconds and the route allows five calls per
  ten, so `with_typing` posts once, refreshes every 8 seconds while your
  work runs, and stops on its own. Refreshing for you is the part every
  hand-rolled version gets wrong, and the docs also say plainly that bots
  generally should not use this route, which is why the wrapper keeps the
  lifetime tied to the work rather than handing back a handle to forget.
  Returns whatever `work` returns, so it composes with a Result. A refused
  indicator is logged, not raised: the indicator is cosmetic and failing
  the operation over it would be the wrong trade.
- reactions: `add_reaction`, `remove_own_reaction` and `get_reaction_users`
  on `rest/endpoints` and on `bot`. The emoji is a new
  `tadpole/model/emoji` `Emoji`, either `Unicode` characters or a
  `Custom(name, id)` pair, because Discord puts the emoji in the path and
  answers `10014: Unknown Emoji` when the segment is not URL encoded.
  That error names the emoji rather than the encoding, so a wrong one
  reads like the wrong emoji, which is reason enough for the wrapper to
  own the encoding rather than the caller. `to_text` gives the unencoded
  form back for logs and command parsing. `EmojiId` joins the other
  opaque ids, so a typo'd custom emoji id fails at construction instead
  of as a 404. `get_reaction_users` returns `ReactionUsers`, shaped like
  `MessagePage` with `next_after`, because Discord pages that route the
  same way it pages history. Note "nobody reacted with that emoji" is a
  404 from Discord, not an empty list.
- the README and the module directory table no longer describe
  `rest/endpoints` as three routes. (#38)

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
