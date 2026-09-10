//// The beginner-facing runner: one config, one handler, one shard.
//// `start` validates the config, opens the gateway, and hands back a Bot
//// whose events arrive at your handler one at a time, in arrival order.
//// The same Bot answers: `send_message` and `reply` post messages over
//// the bot's REST client, and `stop` closes the gateway. Multi-shard
//// fleets, handler supervision, and a stop that ends the program are
//// later work — a handler crash takes the whole bot down, which beats a
//// silently dead bot.
//// Stability: Experimental.
////
//// New here? [`tadpole/guide`](guide.html) walks from an empty directory
//// to a running bot; [`tadpole`](../tadpole.html) builds the config this
//// module consumes.
////
//// ## When you reach for this
////
//// For every first bot. `run` is the entire program: build a config,
//// hand over a handler, block until killed. Reach for `start` instead
//// when something else in the program must keep working alongside the
//// bot — `start` returns a Bot once the shard is up and lets you call
//// `stop` or the REST helpers from any process later. Neither function
//// supports more than one shard; that is refused at startup, not
//// negotiated at runtime.
////
//// ## Failure modes
////
//// Startup failures return `Error` before any process starts, so a
//// rejected config never leaves a half-running bot behind:
////
//// - `MissingToken` / `InvalidTokenFormat` — the token was empty,
////   whitespace, too short, or carried quotes.
//// - `ShardingNotSupported(got)` — the config asked for `got` shards;
////   this milestone runs exactly one.
////
//// After startup, `start` and `run` do not fail again. The shard
//// reconnects on its own and reports through lifecycle notices (below).
//// If the dispatcher process fails to report back within 20 seconds of
//// start, that is a tadpole bug and surfaces as
//// `error.InternalContractViolation`.
////
//// At runtime there is one way to die: an exception in the handler. It
//// crashes the dispatcher, and the dispatcher is linked to the caller of
//// `start`/`run`, so the whole bot comes down loudly. No supervision, no
//// retry-around-handler in this version.
////
//// `send_message` and `reply` fail with `RestStatus` — any non-2xx,
//// where status 0 means no HTTP response happened at all — or with
//// `RateLimited` once 429 retries run out. `stop` never fails.
////
//// ## Lifecycle notices
////
//// The shard reports what happens to the connection; each notice logs
//// through Erlang's `logging` at the config's `log_level` threshold.
//// None of them carry the token.
////
//// - `Connected` (Info) — the websocket handshake succeeded; HELLO has
////   not arrived yet, so identify/resume has not run.
//// - `Disconnected(close_code, will_resume)` (Warn) — the connection
////   closed. The code names the reason (tadpole/gateway's
////   `close_code_name`); `will_resume` says whether the next connection
////   resumes the session or identifies fresh.
//// - `ConnectFailed(error)` (Warn) — one connect attempt failed; a
////   retry is already scheduled with backoff. The logged line stays
////   short; the full error goes to the shard's own logs.
////
//// Repeated `Disconnected` plus `ConnectFailed` notices mean a connect
//// loop, usually a flaky network or a gateway that keeps refusing. A
//// single `Disconnected` with a config close code (4014 disallowed
//// intents, for one) is tadpole stopping on purpose: the docs mark
//// those do-not-reconnect, and no amount of retrying fixes config.
////
//// ## Concurrency
////
//// - `handler` runs in tadpole's dispatcher process. Events are
////   delivered SEQUENTIALLY, one at a time in arrival order: the loop
////   does not read the next event until the handler returns. A slow
////   handler delays everything behind it. In exchange, handler state
////   needs no locks — nothing else ever touches it.
//// - A `Bot` is a plain record, safe to pass to other processes or send
////   in messages. `send_message`, `reply`, and `stop` may be called from
////   any process; each REST call is independent and blocks its calling
////   process for the round trip (plus retries and rate-limit sleeps).
//// - The dispatcher owns the event and lifecycle subjects and is the
////   only process that can receive on them. Everyone else is send-only.
////
//// ## Example
////
//// The shape of a whole bot (token loading omitted; the real program is
//// dev/echo_bot.gleam in the repository):
////
//// ```gleam
//// import gleam/io
//// import tadpole
//// import tadpole/bot
//// import tadpole/error/render
//// import tadpole/gateway/events.{MessageCreate, Ready}
//// import tadpole/intent
////
//// pub fn main() {
////   let cfg =
////     tadpole.new(token())  // from the environment, never source code
////     |> tadpole.with_intents(
////       intent.new()  // Message Content needs a Developer Portal toggle
////       |> intent.enable(intent.guilds)
////       |> intent.enable(intent.guild_messages)
////       |> intent.enable(intent.message_content),
////     )
////
////   case bot.run(cfg, handle_event) {
////     Ok(_) -> Nil
////     Error(e) -> io.println(render.render_error(e))
////   }
//// }
////
//// fn handle_event(tadbot: bot.Bot, event: events.Event) {
////   case event {
////     Ready(user, _) -> io.println("logged in as " <> user.username)
////
////     MessageCreate(message) ->
////       case message.author.bot {
////         // Echoing our own messages would loop forever.
////         True -> Nil
////         False ->
////           case
////             bot.reply(tadbot, message.channel_id, message.id, message.content)
////           {
////             Ok(_sent) -> Nil
////             Error(e) -> io.println(render.render_error(e))
////           }
////       }
////
////     _ -> Nil
////   }
//// }
//// ```
////
//// `run` blocks forever on success; Ctrl+C ends it. Without the Message
//// Content portal toggle, other users' messages arrive with empty
//// content — the gateway connects fine and then withholds the text.
////
//// ## See also
////
//// - [`tadpole`](../tadpole.html) — build and validate the config
//// - [`tadpole/gateway/events`](gateway/events.html) — what the handler receives
//// - [`tadpole/rest/endpoints`](rest/endpoints.html) — REST calls beyond the two helpers
//// - [`tadpole/error/render`](error/render.html) — errors to readable text

import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/option.{None, Some}
import logging
import tadpole
import tadpole/error.{type TadpoleError}
import tadpole/gateway
import tadpole/gateway/events.{type Event}
import tadpole/gateway/shard
import tadpole/intent
import tadpole/model/message.{type Message}
import tadpole/rest.{type RestClient}
import tadpole/rest/endpoints
import tadpole/rest/execute.{type Transport}
import tadpole/types/ids.{type ChannelId, type MessageId}

/// The only gateway URL this milestone speaks: gateway v10, JSON frames.
const gateway_url = "wss://gateway.discord.gg/?v=10&encoding=json"

/// How long `start` waits for its bot process to report back. The shard
/// actor's initialiser can hold a websocket handshake for up to 15s; this
/// leaves room on top of that worst case.
const start_timeout_ms = 20_000

/// A running bot: the validated config, the REST client, the shard's
/// subject, and the transport `send_message`/`reply` fire over. The fields
/// are public so tests can build one by hand with a canned transport;
/// normal code gets a Bot from `start` and passes it around.
pub type Bot {
  Bot(
    /// The config the bot was started with, exactly as passed to `start`.
    config: tadpole.Config,
    /// REST client behind `send_message` and `reply`; hand it to
    /// tadpole/rest/endpoints for calls the bot helpers do not wrap.
    rest: RestClient,
    /// The shard actor. `stop` sends it `shard.Stop`; every other
    /// ShardMsg variant is internal plumbing.
    shard: Subject(shard.ShardMsg),
    /// The token the shard identifies with. Never log it.
    token: String,
    /// The HTTP transport the bot helpers run over — gleam_httpc for bots
    /// built by `start`, anything you like for bots built by hand.
    transport: Transport,
  )
}

/// Validate the config, open one gateway shard, and start dispatching its
/// events to `handler`.
///
/// Fails before any process is started when the token is missing or
/// malformed (`MissingToken` / `InvalidTokenFormat`), or with
/// `ShardingNotSupported` when the config asks for more than one shard.
/// Pass the error to `error/render.render_error` for human-readable next
/// steps.
///
/// Concurrency: `handler` runs in tadpole's dispatcher process. Events are
/// delivered SEQUENTIALLY, one at a time in arrival order — a slow handler
/// delays every event behind it. That is the documented v1 behavior,
/// chosen over concurrent dispatch so handler state needs no locking. A
/// crash in the handler crashes the dispatcher and, through its link, the
/// process that called `start`: fail fast beats a dead bot nobody
/// noticed.
///
///     // Illustrative — dev/echo_bot.gleam is the whole program.
///     let assert Ok(tadbot) = bot.start(config, handle_event)
///     // later, from any process:
///     bot.stop(tadbot)
pub fn start(
  cfg: tadpole.Config,
  handler: fn(Bot, Event) -> Nil,
) -> Result(Bot, TadpoleError) {
  case tadpole.validate(cfg) {
    Error(e) -> Error(e)
    Ok(validated) ->
      case validated.config.shard_count {
        1 -> launch(validated.config, validated.rest, handler)
        got -> Error(error.ShardingNotSupported(got))
      }
  }
}

/// `start`, then block the calling process forever while the bot runs.
///
/// Use this in `main`; use `start` when something else in the program
/// needs to keep working alongside the bot. The program ends when it is
/// killed (Ctrl+C) or when the handler crashes — there is no graceful
/// shutdown yet. Startup failures return immediately: a rejected config
/// never blocks.
pub fn run(
  cfg: tadpole.Config,
  handler: fn(Bot, Event) -> Nil,
) -> Result(Nil, TadpoleError) {
  case start(cfg, handler) {
    Ok(_) -> {
      // Nothing ever sends here; the receive is the park. This process is
      // linked to the dispatcher, so a handler crash ends it too.
      let park = process.new_subject()
      process.receive_forever(park)
    }
    Error(e) -> Error(e)
  }
}

/// POST one text message to a channel, over the bot's REST client.
///
/// Fails with `RestStatus` when Discord answers non-2xx — 403 usually
/// means the bot lacks Send Messages in that channel, 404 that the
/// channel id is wrong — or with `RateLimited` once 429 retries run out.
/// Discord truncates content past 2000 characters silently; tadpole does
/// not second-guess that.
///
///     // Illustrative shape — dev/echo_bot.gleam is the real program.
///     let assert Ok(tadbot) = bot.start(config, handle)
///     case bot.send_message(tadbot, channel, "hello pond") {
///       Ok(_) -> Nil
///       Error(e) -> io.println(render.render_error(e))
///     }
pub fn send_message(
  bot: Bot,
  channel_id: ChannelId,
  content: String,
) -> Result(Message, TadpoleError) {
  endpoints.send_message_with(bot.rest, bot.transport, channel_id, content)
}

/// POST a reply: like `send_message` but carrying a message_reference, so
/// Discord's client shows the original message above the reply and pings
/// its author.
///
/// Fails like `send_message`; a 404 here usually means the replied-to
/// message was already deleted.
pub fn reply(
  bot: Bot,
  channel_id: ChannelId,
  message_id: MessageId,
  content: String,
) -> Result(Message, TadpoleError) {
  endpoints.reply_with(bot.rest, bot.transport, channel_id, message_id, content)
}

/// Close the gateway: sends the shard actor its Stop message.
///
/// Never fails and never blocks — the close is asynchronous, and the shard
/// does not wait for Discord to acknowledge it. The dispatcher keeps
/// running (it holds nothing but memory) and exits when your program
/// does; `run` does not return when you call this. To end the program,
/// kill it as usual.
pub fn stop(bot: Bot) -> Nil {
  process.send(bot.shard, shard.Stop)
}

// ---------------------------------------------------------------------
// Everything below runs in the dispatcher process that `start` spawns.
// ---------------------------------------------------------------------

fn launch(
  cfg: tadpole.Config,
  rest_client: RestClient,
  handler: fn(Bot, Event) -> Nil,
) -> Result(Bot, TadpoleError) {
  let reply = process.new_subject()
  process.spawn(fn() { bot_main(cfg, rest_client, handler, reply) })
  case process.receive(reply, start_timeout_ms) {
    Ok(Ok(bot)) -> Ok(bot)
    Ok(Error(e)) -> Error(e)
    // The dispatcher is linked: a crash there would already have taken
    // this process down. Silence past the deadline is a tadpole bug,
    // not a user error.
    Error(_) ->
      Error(error.InternalContractViolation(
        location: "tadpole/bot.start",
        details: "bot process did not report back within "
          <> int.to_string(start_timeout_ms)
          <> "ms",
        cause: None,
      ))
  }
}

fn bot_main(
  cfg: tadpole.Config,
  rest_client: RestClient,
  handler: fn(Bot, Event) -> Nil,
  reply: Subject(Result(Bot, TadpoleError)),
) -> Nil {
  // Both subjects are created here, in the dispatcher, because a subject
  // can only be received on by its owner — and this process reads them
  // for the bot's whole life. Everyone else may send.
  let events_subject = process.new_subject()
  let lifecycle = process.new_subject()
  let shard_config =
    shard.ShardConfig(
      token: cfg.token,
      intents: intent.to_int(cfg.intents),
      shard: #(0, cfg.shard_count),
      url: gateway_url,
      lifecycle: Some(lifecycle),
    )
  case shard.start(shard_config, events: events_subject) {
    Ok(shard_subject) -> {
      let bot =
        Bot(
          config: cfg,
          rest: rest_client,
          shard: shard_subject,
          token: cfg.token,
          transport: execute.httpc_transport(cfg.rest_timeout_ms),
        )
      process.send(reply, Ok(bot))
      dispatch_loop(bot, handler, events_subject, lifecycle, cfg.log_level)
    }
    Error(e) -> process.send(reply, Error(e))
  }
}

type Notice {
  GotEvent(Event)
  GotLifecycle(shard.Lifecycle)
}

/// The event loop. Events reach `handler` strictly one at a time: the
/// recursion does not run again until the handler returns. Lifecycle
/// notices from the shard log at the configured threshold and never
/// contain the token.
fn dispatch_loop(
  bot: Bot,
  handler: fn(Bot, Event) -> Nil,
  events_subject: Subject(Event),
  lifecycle: Subject(shard.Lifecycle),
  threshold: tadpole.LogLevel,
) -> Nil {
  let selector =
    process.new_selector()
    |> process.select_map(events_subject, GotEvent)
    |> process.select_map(lifecycle, GotLifecycle)
  case process.selector_receive_forever(selector) {
    GotEvent(event) -> {
      handler(bot, event)
      dispatch_loop(bot, handler, events_subject, lifecycle, threshold)
    }
    GotLifecycle(notice) -> {
      log_notice(threshold, notice)
      dispatch_loop(bot, handler, events_subject, lifecycle, threshold)
    }
  }
}

fn log_notice(threshold: tadpole.LogLevel, notice: shard.Lifecycle) -> Nil {
  let level = notice_level(notice)
  case level_clears(threshold, level) {
    True -> logging.log(to_logging_level(level), notice_text(notice))
    False -> Nil
  }
}

fn notice_level(notice: shard.Lifecycle) -> tadpole.LogLevel {
  case notice {
    shard.Connected -> tadpole.Info
    shard.Disconnected(_, _) -> tadpole.Warn
    shard.ConnectFailed(_) -> tadpole.Warn
  }
}

fn level_clears(threshold: tadpole.LogLevel, level: tadpole.LogLevel) -> Bool {
  rank(level) >= rank(threshold)
}

fn rank(level: tadpole.LogLevel) -> Int {
  case level {
    tadpole.Debug -> 0
    tadpole.Info -> 1
    tadpole.Warn -> 2
    tadpole.ErrorLevel -> 3
  }
}

fn to_logging_level(level: tadpole.LogLevel) -> logging.LogLevel {
  case level {
    tadpole.Debug -> logging.Debug
    tadpole.Info -> logging.Info
    tadpole.Warn -> logging.Warning
    tadpole.ErrorLevel -> logging.Error
  }
}

fn notice_text(notice: shard.Lifecycle) -> String {
  case notice {
    shard.Connected -> "bot: shard connected, waiting for HELLO"
    shard.Disconnected(code, will_resume) ->
      "bot: shard disconnected ("
      <> int.to_string(code)
      <> " "
      <> gateway.close_code_name(code)
      <> "); "
      <> case will_resume {
        True -> "session will resume"
        False -> "next connection identifies fresh"
      }
    // The rendered error is multi-line and a retrying connect loop would
    // spam it every attempt; the shard's own logs carry the details.
    shard.ConnectFailed(_) -> "bot: shard connect failed, retrying with backoff"
  }
}
