//// The walkthrough. Read it top to bottom: empty directory to a bot
//// that echoes messages, then the vocabulary to bend it into whatever
//// you actually wanted. Every claim here was checked against the
//// source of this version; where a feature does not exist the guide
//// says so instead of letting you find out at runtime. The full
//// example program lives in the repository at dev/echo_bot.gleam.
////
//// ## Your first bot
////
//// You need Gleam 1.18 or newer and Erlang/OTP. On Windows, the Erlang
//// installer does not add itself to PATH; add `...\Erlang OTP\bin` by
//// hand once and move on.
////
//// ```sh
//// gleam new my_bot
//// cd my_bot
//// gleam add tadpole
//// ```
////
//// A token comes from the Discord Developer Portal
//// (https://discord.com/developers/applications): New Application,
//// then Bot, then Reset Token. The portal shows it in full only right
//// after a reset; copy it then. The token is the bot's whole identity.
//// Anyone holding it speaks as your bot, and a leaked token is fixed
//// by resetting it, not by hoping.
////
//// Keep the token out of source code. The examples read it from the
//// environment:
////
//// ```sh
//// $env:TADPOLE_TOKEN = "your-token"    # PowerShell
//// export TADPOLE_TOKEN="your-token"    # POSIX shells
//// ```
////
//// Here is the whole program. It is dev/echo_bot.gleam from the
//// repository, verbatim; in your own project paste it into
//// src/my_bot.gleam:
////
//// ```gleam
//// import gleam/io
//// import gleam/list
//// import gleam/string
//// import tadpole
//// import tadpole/bot
//// import tadpole/error/render
//// import tadpole/gateway/events.{type Event, MessageCreate, Ready}
//// import tadpole/intent
////
//// pub fn main() {
////   case env("TADPOLE_TOKEN") {
////     Ok(token) if token != "" -> run(token)
////     _ ->
////       io.println(
////         "echo_bot: no token found.\n"
////         <> "  1. Create a bot and copy its token: "
////         <> "https://discord.com/developers/applications → Bot → Reset Token\n"
////         <> "  2. Set it: $env:TADPOLE_TOKEN = \"your-token\" then run "
////         <> "gleam run -m echo_bot",
////       )
////   }
//// }
////
//// fn run(token: String) {
////   let cfg =
////     tadpole.new(token)
////     |> tadpole.with_intents(
////       intent.new()
////       |> intent.enable(intent.guilds)
////       |> intent.enable(intent.guild_messages)
////       |> intent.enable(intent.message_content),
////     )
////
////   // Message Content is privileged: without the portal toggle Discord
////   // hangs up with close code 4014 the moment we identify.
////   case tadpole.privileged_intents_requested(cfg) {
////     [] -> Nil
////     privileged ->
////       io.println(
////         "echo_bot: this config requests privileged intents ("
////         <> join_names(privileged)
////         <> "). Enable them in the Discord Developer Portal → Bot → "
////         <> "Privileged Gateway Intents, or the gateway will close the "
////         <> "connection with code 4014 (disallowed intents).",
////       )
////   }
////
////   case bot.run(cfg, handle_event) {
////     Ok(_) -> Nil
////     Error(e) -> io.println(render.render_error(e))
////   }
//// }
////
//// fn handle_event(tadbot: bot.Bot, event: Event) {
////   case event {
////     Ready(user, _) -> io.println("logged in as " <> user.username)
////
////     MessageCreate(message) ->
////       case message.author.bot {
////         // Echoing our own messages would loop forever; empty content is
////         // an embed-only post, which a plain text reply cannot echo.
////         True -> Nil
////         False ->
////           case message.content {
////             "" -> Nil
////             content -> {
////               let result =
////                 bot.reply(tadbot, message.channel_id, message.id, content)
////               case result {
////                 Ok(_) -> Nil
////                 Error(e) -> io.println(render.render_error(e))
////               }
////             }
////           }
////       }
////
////     _ -> Nil
////   }
//// }
////
//// fn join_names(bits: List(Int)) -> String {
////   bits
////   |> list.map(intent.intent_name)
////   |> string.join(", ")
//// }
////
//// @external(erlang, "tadpole_ffi", "get_env")
//// fn env(name: String) -> Result(String, Nil)
//// ```
////
//// One footnote before running it: the last two lines read an
//// environment variable, and Gleam's standard library has no binding
//// for that. The example borrows `tadpole_ffi`, an eight-line Erlang
//// module that ships with tadpole. It is private to the package and
//// allowed to move between versions. When that bothers you, put the
//// same function in your own project as src/env_ffi.erl and point the
//// `@external` at `env_ffi` instead:
////
//// ```erlang
//// -module(env_ffi).
//// -export([get_env/1]).
////
//// get_env(Name) ->
////     case os:getenv(unicode:characters_to_list(Name)) of
////         false -> {error, nil};
////         Value -> {ok, unicode:characters_to_binary(Value)}
////     end.
//// ```
////
//// Run it with `gleam run` from the project directory. Inside the
//// tadpole repository itself, the same file starts with
//// `gleam run -m echo_bot`.
////
//// What you should see, in order:
////
//// - the privileged-intents warning, because the config turns on
////   Message Content (next section);
//// - `logged in as <your bot's username>` once READY arrives;
//// - occasional lifecycle lines from Erlang's logger — connects and
////   disconnects go through `logging`, not `io.println`, so whether
////   you see them depends on your logger's level.
////
//// Then post a message in a channel the bot can see. It replies with
//// the same text. It ignores its own messages (that way lies an
//// infinite loop) and messages with no text content. Ctrl+C ends the
//// program; there is no graceful shutdown yet. With no TADPOLE_TOKEN
//// set, the bot prints where to get one and exits without connecting
//// anywhere.
////
//// ## Privileged intents
////
//// Three gateway intents sit behind toggles in the Developer Portal:
//// Server Members (`intent.guild_members`), Presence
//// (`intent.guild_presences`), and Message Content
//// (`intent.message_content`). These are the three entries in
//// `intent.privileged`. Requesting any of them without the matching
//// toggle ends the connection.
////
//// For an echo bot the one that matters is Message Content: without
//// it, `message.content` arrives empty for messages authored by other
//// users, and there is nothing to echo.
////
//// The toggle lives at Developer Portal → Bot → Privileged Gateway
//// Intents. Enable, Save Changes, restart the bot. tadpole cannot
//// check the portal for you: `tadpole.validate` reports the
//// privileged bits a config requests — that is what
//// `tadpole.privileged_intents_requested` returns — and refuses
//// nothing, because Discord does the enforcing.
////
//// Enforcement looks like this: the bot identifies, Discord closes
//// the connection with close code 4014 (disallowed intents), and
//// tadpole stops reconnecting. The docs mark 4014 as do-not-reconnect;
//// it is a config problem, and retrying cannot fix it. The lifecycle
//// log names the code once: toggle the intents on or drop them from
//// the config, then start the bot again. The echo bot prints its
//// warning before any of that, for exactly this reason.
////
//// ## Responding to events
////
//// A handler is `fn(Bot, Event) -> Nil`, and `Event` is a plain
//// Gleam type from [`tadpole/gateway/events`](gateway/events.html).
//// The variants:
////
//// ```gleam
//// pub type Event {
////   Ready(ready_user: User, guild_count: Int)
////   MessageCreate(message: Message)
////   MessageUpdate(update: MessageUpdate)
////   MessageDelete(
////     id: MessageId,
////     channel_id: ChannelId,
////     guild_id: Option(GuildId),
////   )
////   Resumed
////   GuildCreate(guild: Guild)
////   GuildDelete(unavailable: UnavailableGuild)
////   Unknown(name: String, raw: String)
//// }
//// ```
////
//// A skeleton that does nothing but talk:
////
//// ```gleam
//// import gleam/int
//// import gleam/io
//// import gleam/option.{None, Some}
//// import tadpole/bot
//// import tadpole/gateway/events.{
////   type Event, GuildCreate, GuildDelete, MessageCreate, MessageDelete,
////   MessageUpdate, Ready, Resumed, Unknown,
//// }
//// import tadpole/types/ids
////
//// fn handle_event(_tadbot: bot.Bot, event: Event) -> Nil {
////   case event {
////     Ready(user, guild_count) ->
////       io.println(
////         "logged in as " <> user.username <> " ("
////         <> int.to_string(guild_count) <> " guilds to arrive)",
////       )
////
////     MessageCreate(message) ->
////       io.println(message.author.username <> ": " <> message.content)
////
////     MessageUpdate(update) ->
////       case update.content {
////         Some(text) -> io.println("edited: " <> text)
////         None -> Nil
////       }
////
////     MessageDelete(id, _channel_id, _guild_id) ->
////       io.println("deleted: " <> ids.message_to_string(id))
////
////     Resumed -> io.println("reconnected; missed events replayed")
////
////     GuildCreate(guild) -> io.println("guild ready: " <> guild.name)
////
////     GuildDelete(unavailable) ->
////       io.println("guild gone: " <> ids.guild_to_string(unavailable.id))
////
////     Unknown(name, _) -> io.println("unmodeled event: " <> name)
////   }
//// }
//// ```
////
//// Three shapes worth knowing. `Unknown` carries every event this
//// version does not model, with its name and raw payload: Discord
//// ships new event types on its own schedule, and a bot should
//// degrade to data instead of crashing on the ones tadpole has not
//// met. `MessageDelete`'s `guild_id` is `None` in DMs. `Ready`'s
//// `guild_count` counts what READY promised; each guild lands as its
//// own `GuildCreate` moments later.
////
//// Dispatch is sequential. Events reach the handler one at a time, in
//// arrival order, and a slow handler delays everything behind it. A
//// crash in the handler takes the bot down. Both are deliberate for
//// this version: sequential delivery means handler state needs no
//// locks, and a bot that dies loudly beats a bot that silently stops
//// caring. Supervised handlers and concurrent dispatch are later
//// work, not hidden features.
////
//// ## Sending messages
////
//// The handler receives a `Bot`, and the `Bot` carries the REST
//// client:
////
//// ```gleam
//// import gleam/io
//// import tadpole/bot
//// import tadpole/error/render
//// import tadpole/gateway/events.{type Event, MessageCreate}
////
//// fn handle_event(tadbot: bot.Bot, event: Event) -> Nil {
////   case event {
////     MessageCreate(message) ->
////       case message.author.bot {
////         True -> Nil
////         False -> {
////           let answer = "you said: " <> message.content
////           case bot.send_message(tadbot, message.channel_id, answer) {
////             Ok(_sent) -> Nil
////             Error(e) -> io.println(render.render_error(e))
////           }
////         }
////       }
////
////     _ -> Nil
////   }
//// }
//// ```
////
//// `bot.reply` takes the same arguments plus a `MessageId` and sends
//// with a message_reference: Discord's client draws the original
//// above the reply and pings its author. Both return the posted
//// `Message` on success.
////
//// Channel IDs come typed out of events — `message.channel_id` is
//// already a `ChannelId`. An ID you hold as a string goes through the
//// constructor, which validates it as a snowflake (add
//// `import tadpole/types/ids`):
////
//// ```gleam
//// case ids.channel_id("123456789012345678") {
////   Ok(channel) -> bot.send_message(tadbot, channel, "hello pond")
////   Error(_invalid) -> io.println("that was not a snowflake")
//// }
//// ```
////
//// Failure modes, straight from the function docs: a 403 usually
//// means the bot lacks Send Messages in that channel; a 404 means the
//// channel ID is wrong — or, for `reply`, that the replied-to message
//// was already deleted.
////
//// Discord truncates content past 2000 characters, silently. The
//// message goes through, the tail is gone, no error comes back, and
//// tadpole does not second-guess it. Check `string.length` before
//// sending if the length matters to you.
////
//// Rate limits: waits are learned from response headers and 429
//// bodies, and 429s are retried while retries remain (`retry_on_429`
//// and `max_retries` in the config). Each call through the bot
//// helpers runs in its own rate-limit session — fine for a few
//// messages, but a tight loop leans on retries instead of learned
//// waits; sustained fire belongs in
//// [`tadpole/rest/execute`](rest/execute.html)'s
//// `send_in_session`.
////
//// ## Errors
////
//// Errors are values. Nothing in tadpole's public API panics; every
//// fallible call returns `Result` with a `TadpoleError`, and the
//// variants carry structure — route, status, retry-after, decode
//// path — so you can match on them, not just print them.
////
//// [`tadpole/error/render`](error/render.html) turns any of
//// them into text a human can act on:
////
//// ```gleam
//// case bot.run(cfg, handle_event) {
////   Ok(_) -> Nil
////   Error(e) -> io.println(render.render_error(e))
//// }
//// ```
////
//// For control flow, match the variant and fall back to the renderer
//// for the rest:
////
//// ```gleam
//// import gleam/int
//// import tadpole/error
////
//// case bot.send_message(tadbot, channel, content) {
////   Ok(_sent) -> Nil
////   Error(error.RateLimited(route, retry_after_ms, _is_global, _bucket)) ->
////     io.println(
////       "rate limited on " <> error.route_to_string(route)
////       <> "; wait " <> int.to_string(retry_after_ms) <> "ms",
////     )
////   Error(e) -> io.println(render.render_error(e))
//// }
//// ```
////
//// With `retry_on_429` on (the default), a `RateLimited` that reaches
//// your code means the retries ran out. The renderer has a severity
//// ladder: ordinary hiccups get a friendly line, severe failures get
//// quiet text with a straight list of things to try, and a bug in
//// tadpole itself gets an apology and a report request.
////
//// The token is redacted everywhere it could show up. Config
//// descriptions and rendered errors keep the first four and last four
//// characters and hide the rest; the test suite asserts that a planted
//// full token never appears in rendered output.
////
//// ## Going further
////
//// The directory, one line per module:
////
//// | Module | What it is | Audience |
//// | --- | --- | --- |
//// | [`tadpole`](../tadpole.html) | config builder: `new`, `with_*`, `validate` | start here |
//// | [`tadpole/bot`](bot.html) | the runner: `start`, `run`, `send_message`, `reply`, `stop` | beginner |
//// | [`tadpole/gateway/events`](gateway/events.html) | the typed `Event` type and its decoder | beginner |
//// | [`tadpole/intent`](intent.html) | intents bitfield, privileged detection | beginner |
//// | [`tadpole/error`](error.html) | every failure as a typed value | beginner |
//// | [`tadpole/error/render`](error/render.html) | errors to human text, token redacted | beginner |
//// | [`tadpole/types/ids`](types/ids.html) | opaque IDs, so a UserId cannot go where a GuildId goes | beginner |
//// | [`tadpole/rest/endpoints`](rest/endpoints.html) | GET /users/@me, post a message, reply | beginner |
//// | [`tadpole/model/user`](model/user.html) | the user object | beginner |
//// | [`tadpole/model/message`](model/message.html) | the message object and MESSAGE_UPDATE's partial form | beginner |
//// | [`tadpole/model/guild`](model/guild.html) | the guild object and the unavailable stub | beginner |
//// | [`tadpole/model/channel`](model/channel.html) | the channel object, trimmed | beginner |
//// | [`tadpole/gateway/shard`](gateway/shard.html) | one gateway connection: heartbeats, identify/resume, backoff | internals |
//// | [`tadpole/gateway/transport`](gateway/transport.html) | the stratus websocket behind a wall | internals |
//// | [`tadpole/gateway/frame`](gateway/frame.html) | envelope parsing and building: `{op, d, s, t}` | internals |
//// | [`tadpole/gateway/opcode`](gateway/opcode.html) | gateway opcodes, with a slot for ones Discord adds later | internals |
//// | [`tadpole/gateway/identify_gate`](gateway/identify_gate.html) | identify pacing across shards; /gateway/bot wiring is later | internals |
//// | [`tadpole/gateway`](gateway.html) | pure protocol decisions: close codes, backoff, sharding math | internals |
//// | [`tadpole/event_type`](event_type.html) | event name to category and required intents | internals |
//// | [`tadpole/rest`](rest.html) | request builders, header-derived rate-limit parsing | internals |
//// | [`tadpole/rest/execute`](rest/execute.html) | transport injection, 429 retries, rate-limit sessions | internals |
//// | [`tadpole/rest/rate_limit`](rest/rate_limit.html) | per-bucket limit state, pure | internals |
//// | [`tadpole/model/decode`](model/decode.html) | shared decoder plumbing | internals |
//// | [`tadpole/types/snowflake`](types/snowflake.html) | 64-bit snowflakes, timestamp extraction | internals |
////
//// What tadpole does not do yet, so nobody spends an afternoon
//// finding out:
////
//// - multi-shard. `with_shards(n)` past 1 is refused with
////   `ShardingNotSupported` before anything connects.
//// - interactions and slash commands
//// - embeds, file uploads, message components
//// - voice
//// - a cache. Every event is what Discord just sent; nothing is
////   remembered between events.
//// - graceful shutdown. `bot.stop` closes the gateway; the program
////   ends the usual way.
////
//// Each module's doc header declares a stability tier (Stable,
//// Growing, Experimental) under the policy in CONTRIBUTING.md. Most
//// of this slice is Growing or Experimental, which is the honest way
//// to say the API can still move.
////
//// ## See also
////
//// - [`tadpole`](../tadpole.html) — the config builder the walkthrough uses
//// - [`tadpole/bot`](bot.html) — the runner the walkthrough builds on

/// The guide is a documentation-only module, and HexDocs wants at
/// least one public item per page, so this is it. It returns Nil and
/// has no other opinion.
pub fn start_here() -> Nil {
  Nil
}
