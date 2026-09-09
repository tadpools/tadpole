//// Tadpole: a Discord library for Gleam. Every frog starts as a
//// tadpole. This module is where a bot begins: `new` builds a config,
//// `with_*` adjusts it, `validate` checks it before anything connects.
//// The network hangs off `ValidatedConfig`; the runner that uses it is
//// tadpole/bot.
////
//// New here? [`tadpole/guide`](tadpole/guide.html) walks from an empty
//// directory to a running echo bot.
////
//// ## The shape of the library
////
//// ```text
////        your handler (fn(Bot, Event) -> Nil)
////          ^ |
////          | | bot.send_message / bot.reply
////          | v
////      tadpole/bot  (the runner: validates, connects, dispatches
////          |         events one at a time, in arrival order)
////          |                \
////     events                 |  REST calls
////          v                 v
////      tadpole/gateway/shard   tadpole/rest/execute
////        (heartbeats, identify   (rate limits learned from
////         or resume, backoff)     response headers, 429 retries)
////          |                       |
////      tadpole/gateway/transport   gleam_httpc
////        (stratus websocket)       |
////          |                       v
////          v                   Discord REST API
////      Discord gateway (wss)
//// ```
////
//// The two sides never share state: the gateway delivers events, REST
//// sends answers. A `Bot` from `bot.start` holds both handles.
////
//// ## Module directory
////
//// | Module | What it owns | Audience |
//// | --- | --- | --- |
//// | [`tadpole`](tadpole.html) | config builder: `new`, `with_*`, `validate`, `describe_config` | beginner |
//// | [`tadpole/bot`](tadpole/bot.html) | the runner: `start`, `run`, `send_message`, `reply`, `stop`; one shard | beginner |
//// | [`tadpole/guide`](tadpole/guide.html) | the walkthrough | beginner |
//// | [`tadpole/gateway/events`](tadpole/gateway/events.html) | the typed `Event` type: Ready, MessageCreate, Unknown, ... | beginner |
//// | [`tadpole/intent`](tadpole/intent.html) | intents bitfield, privileged-intent detection | beginner |
//// | [`tadpole/error`](tadpole/error.html) | every failure as a typed value | beginner |
//// | [`tadpole/error/render`](tadpole/error/render.html) | errors to human text; token redacted everywhere | beginner |
//// | [`tadpole/types/ids`](tadpole/types/ids.html) | opaque IDs, so a UserId cannot go where a GuildId goes | beginner |
//// | [`tadpole/rest/endpoints`](tadpole/rest/endpoints.html) | GET /users/@me, post a message, reply | beginner |
//// | [`tadpole/model/user`](tadpole/model/user.html) | the user object | beginner |
//// | [`tadpole/model/message`](tadpole/model/message.html) | the message object and MESSAGE_UPDATE's partial form | beginner |
//// | [`tadpole/model/guild`](tadpole/model/guild.html) | the guild object and the unavailable stub | beginner |
//// | [`tadpole/model/channel`](tadpole/model/channel.html) | the channel object, trimmed | beginner |
//// | [`tadpole/gateway/shard`](tadpole/gateway/shard.html) | one gateway connection, end to end | internals |
//// | [`tadpole/gateway/transport`](tadpole/gateway/transport.html) | the stratus websocket behind a wall | internals |
//// | [`tadpole/gateway/frame`](tadpole/gateway/frame.html) | frame envelope parsing and building: `{op, d, s, t}` | internals |
//// | [`tadpole/gateway/opcode`](tadpole/gateway/opcode.html) | gateway opcodes, with a slot for ones Discord adds later | internals |
//// | [`tadpole/gateway/identify_gate`](tadpole/gateway/identify_gate.html) | identify pacing across a fleet; /gateway/bot wiring is later | internals |
//// | [`tadpole/gateway`](tadpole/gateway.html) | pure protocol decisions: close codes, backoff, sharding math | internals |
//// | [`tadpole/event_type`](tadpole/event_type.html) | event name to category and required intents | internals |
//// | [`tadpole/rest`](tadpole/rest.html) | request builders, header-derived rate-limit parsing | internals |
//// | [`tadpole/rest/execute`](tadpole/rest/execute.html) | transport injection, 429 retries, rate-limit sessions | internals |
//// | [`tadpole/rest/rate_limit`](tadpole/rest/rate_limit.html) | per-bucket limit state, pure | internals |
//// | [`tadpole/model/decode`](tadpole/model/decode.html) | shared decoder plumbing | internals |
//// | [`tadpole/types/snowflake`](tadpole/types/snowflake.html) | 64-bit snowflakes, timestamp extraction | internals |
////
//// "Internals" means you can use it, but the API moves more freely and
//// a newer milestone may ask you to re-read the docs.
////
//// ## Status and stability
////
//// The first vertical slice works: a bot connects to the gateway,
//// identifies, heartbeats on Discord's interval, resumes after a
//// disconnect, reconnects with backoff, and receives typed events.
//// REST runs over gleam_httpc with rate limits taken from response
//// headers and 429 bodies — no hardcoded bucket table.
////
//// Not here yet — do not assume it:
////
//// - multi-shard. A config asking for more than one shard is refused
////   with `ShardingNotSupported` before anything connects.
//// - interactions and slash commands
//// - embeds, file uploads, message components
//// - voice
//// - a cache. Every event is what Discord just sent; nothing is
////   remembered between events.
//// - graceful shutdown. `bot.stop` closes the gateway; the program
////   ends the usual way.
////
//// Each module's `////` header declares a stability tier (Stable,
//// Growing, Experimental) under the policy in CONTRIBUTING.md. Most of
//// this slice is Growing or Experimental.
////
//// The package is not on Hex yet. CONTRIBUTING.md gates publishing on
//// one live roundtrip — gateway connect through ready, plus one real
//// REST call — and that gate has not been tripped. Until then the
//// changelog and the test suite are the contract.

import gleam/int
import gleam/string
import tadpole/error.{type TadpoleError, InvalidTokenFormat, MissingToken}
import tadpole/intent.{type Intents}
import tadpole/rest.{type RestClient}

pub type LogLevel {
  Debug
  Info
  Warn
  ErrorLevel
}

pub type Config {
  Config(
    token: String,
    intents: Intents,
    shard_count: Int,
    rest_timeout_ms: Int,
    retry_on_429: Bool,
    max_retries: Int,
    gateway_reconnect: Bool,
    log_level: LogLevel,
  )
}

pub fn new(token: String) -> Config {
  Config(
    token: token,
    intents: intent.new(),
    shard_count: 1,
    rest_timeout_ms: 30_000,
    retry_on_429: True,
    max_retries: 3,
    gateway_reconnect: True,
    log_level: Info,
  )
}

pub fn with_intents(config: Config, intents: Intents) -> Config {
  Config(..config, intents: intents)
}

pub fn with_shards(config: Config, count: Int) -> Config {
  Config(..config, shard_count: count)
}

pub fn with_rest_timeout(config: Config, timeout_ms: Int) -> Config {
  Config(..config, rest_timeout_ms: timeout_ms)
}

pub fn with_retry_on_429(config: Config, enabled: Bool) -> Config {
  Config(..config, retry_on_429: enabled)
}

pub fn with_max_retries(config: Config, max: Int) -> Config {
  Config(..config, max_retries: max)
}

pub fn with_gateway_reconnect(config: Config, enabled: Bool) -> Config {
  Config(..config, gateway_reconnect: enabled)
}

pub fn with_log_level(config: Config, level: LogLevel) -> Config {
  Config(..config, log_level: level)
}

pub type ValidatedConfig {
  ValidatedConfig(config: Config, rest: RestClient)
}

/// Validation errors before any connection is attempted: empty or
/// malformed tokens. Privileged intents are reported, not rejected —
/// Discord enforces those at Identify with close code 4014.
pub fn validate(config: Config) -> Result(ValidatedConfig, TadpoleError) {
  case validate_token(config.token) {
    Ok(_) -> Ok(ValidatedConfig(config: config, rest: build_rest(config)))
    Error(e) -> Error(e)
  }
}

pub fn privileged_intents_requested(config: Config) -> List(Int) {
  intent.check_privileged(config.intents)
}

/// Safe to log: token redacted.
pub fn describe_config(config: Config) -> String {
  "tadpole config: "
  <> int.to_string(config.shard_count)
  <> " shard(s), intents ["
  <> intent.to_string(config.intents)
  <> "], token "
  <> error.redact_token(config.token)
}

fn validate_token(token: String) -> Result(Nil, TadpoleError) {
  case string.trim(token) {
    "" -> Error(MissingToken)
    trimmed ->
      case
        string.length(trimmed) < 50
        || contains_any(trimmed, [" ", "\n", "\t", "\"", "'"])
      {
        True -> Error(InvalidTokenFormat(trimmed))
        False -> Ok(Nil)
      }
  }
}

fn contains_any(haystack: String, needles: List(String)) -> Bool {
  case needles {
    [] -> False
    [needle, ..rest] ->
      case string.contains(haystack, needle) {
        True -> True
        False -> contains_any(haystack, rest)
      }
  }
}

fn build_rest(config: Config) -> RestClient {
  rest.new_client(
    config.token,
    config.rest_timeout_ms,
    config.retry_on_429,
    config.max_retries,
  )
}
