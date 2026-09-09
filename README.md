# tadpole

A Discord library for Gleam. Every frog starts as a tadpole.

![](assets/tadpole.gif)

## why tadpole

Most Discord libraries are written for dynamic languages first. Tadpole
is Gleam and OTP first, and the API is shaped by that choice:

- **Opaque IDs.** `UserId`, `GuildId`, `ChannelId`, and `MessageId`
  are distinct types (tadpole/types/ids). Passing a `GuildId` where a
  `ChannelId` belongs is a compile error, not a 400 from Discord.

- **Typed events.** The handler matches on `Ready`, `MessageCreate`,
  and `Resumed` (tadpole/gateway/events). Events Tadpole does not
  model yet arrive as `Unknown` with the raw payload attached, so a
  new Discord event becomes data you can log instead of a crash.

- **Typed errors.** Every failure is a variant with context:
  `RateLimited` carries the retry window in milliseconds, `RestStatus`
  carries the route, status, and Discord's error body. Recover with
  pattern matching, not string parsing. The opt-in renderer prints
  what happened and what to try, and redacts the token on every path
  (tadpole/error, tadpole/error/render).

- **Managed reconnection.** The shard actor owns the session:
  heartbeats on Discord's interval with zombie detection, a decision
  per close code, resume when the session allows it, and backoff
  between attempts (tadpole/gateway/shard). A dropped websocket is
  handled, not fatal.

- **Runtime rate limits.** Buckets, remaining counts, and retry
  windows are read from response headers and 429 bodies at runtime
  (tadpole/rest/rate_limit). Nothing is hardcoded against a snapshot
  of Discord's buckets.

- **One API at several depths.** `bot.run` is a thin layer over the
  same public modules it drives; it calls `shard.start` the way you
  would (tadpole/bot). When one config and one handler stop being
  enough, the layer below is already public.

Also included: endpoint bindings for `GET /users/@me`, sending a
message, and replying (tadpole/rest/endpoints); model objects whose
decoders report where a payload stopped matching (tadpole/model); and
config validation that redacts the token in its own describe output
(tadpole.describe_config).

A first bot and a sharded production bot should be the same framework
at different sizes: growth is additive, and nothing you wrote at
hello-world gets renamed when you need more. That contract lives in
CONTRIBUTING.md, and reviewers hold changes to it.

## where this actually is

The first vertical slice works. A bot can connect to Discord's gateway,
identify, heartbeat, resume after a disconnect, and receive typed events.
REST calls run over gleam_httpc with rate-limit handling learned from
response headers. The echo bot below is a complete program.

Not here yet, so do not assume it:

- multi-shard. One shard. A config asking for more is refused with
  `ShardingNotSupported` before anything connects.
- interactions and slash commands
- embeds, file uploads, message components
- voice
- a cache. Every event is what Discord just sent; nothing is remembered
  between events.
- member lists or presence beyond what rides along in other payloads
- graceful shutdown. `bot.stop` closes the gateway; the program ends the
  usual way.

One honest caveat: everything above is tested against recorded payload
shapes and canned HTTP responses. It has not run against real Discord
from CI, and the package is not on Hex yet. The publish gate in
CONTRIBUTING.md requires one live roundtrip (gateway connect through
ready, plus one real REST call) first, and that check has not happened
yet. Adjust trust accordingly.

## a whole bot

Gleam 1.18+ and Erlang/OTP.

    gleam add tadpole        # not on Hex yet; the publish gate comes first
    $env:TADPOLE_TOKEN = "your-bot-token"   # PowerShell

This program lives locally in dev/echo_bot.gleam. That folder stays out
of version control because it holds token-driven scripts, so the listing
above is the copy to trust. The `env` helper at the bottom is the only
Erlang in the program; tadpole ships it, though it is private and
allowed to move.

```gleam
import gleam/io
import gleam/list
import gleam/string
import tadpole
import tadpole/bot
import tadpole/error/render
import tadpole/gateway/events.{type Event, MessageCreate, Ready}
import tadpole/intent

pub fn main() {
  case env("TADPOLE_TOKEN") {
    Ok(token) if token != "" -> run(token)
    _ ->
      io.println(
        "echo_bot: no token found.\n"
        <> "  1. Create a bot and copy its token: "
        <> "https://discord.com/developers/applications → Bot → Reset Token\n"
        <> "  2. Set it: $env:TADPOLE_TOKEN = \"your-token\" then run "
        <> "gleam run -m echo_bot",
      )
  }
}

fn run(token: String) {
  let cfg =
    tadpole.new(token)
    |> tadpole.with_intents(
      intent.new()
      |> intent.enable(intent.guilds)
      |> intent.enable(intent.guild_messages)
      |> intent.enable(intent.message_content),
    )

  // Message Content is privileged: without the portal toggle Discord
  // hangs up with close code 4014 the moment we identify.
  case tadpole.privileged_intents_requested(cfg) {
    [] -> Nil
    privileged ->
      io.println(
        "echo_bot: this config requests privileged intents ("
        <> join_names(privileged)
        <> "). Enable them in the Discord Developer Portal → Bot → "
        <> "Privileged Gateway Intents, or the gateway will close the "
        <> "connection with code 4014 (disallowed intents).",
      )
  }

  case bot.run(cfg, handle_event) {
    Ok(_) -> Nil
    Error(e) -> io.println(render.render_error(e))
  }
}

fn handle_event(tadbot: bot.Bot, event: Event) {
  case event {
    Ready(user, _) -> io.println("logged in as " <> user.username)

    MessageCreate(message) ->
      case message.author.bot {
        // Echoing our own messages would loop forever; empty content is
        // an embed-only post, which a plain text reply cannot echo.
        True -> Nil
        False ->
          case message.content {
            "" -> Nil
            content -> {
              let result =
                bot.reply(tadbot, message.channel_id, message.id, content)
              case result {
                Ok(_) -> Nil
                Error(e) -> io.println(render.render_error(e))
              }
            }
          }
      }

    _ -> Nil
  }
}

fn join_names(bits: List(Int)) -> String {
  bits
  |> list.map(intent.intent_name)
  |> string.join(", ")
}

@external(erlang, "tadpole_ffi", "get_env")
fn env(name: String) -> Result(String, Nil)
```

To run it against this repo's source, save the program as
dev/echo_bot.gleam in your clone. The dev/ folder is gitignored, so it
is yours to create, and `gleam run -m echo_bot` picks the module up
from there:

    gleam run -m echo_bot

Message Content is a privileged intent. Enable it in the Discord
Developer Portal (Bot → Privileged Gateway Intents) or drop it from the
config. Without the toggle, Discord hangs up with close code 4014 the
moment the bot identifies. The example prints a reminder before that
happens; it cannot check the portal for you.

## running the tests

    gleam test

All tests run against recorded fixtures and canned HTTP responses. No
network in CI. The suite has three layers (unit, property, contract);
TESTING.md is the map: what each layer is for and how to add to it.

Smoke runs against real Discord happen by hand, never from CI, with a
token in `TADPOLE_TOKEN`. The smoke scripts live in dev/ and are not
part of the published tree; they are how the publish gate gets run.
Both exit immediately without the token set:

    gleam run -m echo_bot     # the echo bot: repeats non-bot messages
    gleam run -m smoke_gw     # connects one shard, prints events for 60s, exits

Windows note: the Erlang installer doesn't add itself to PATH. Add
`C:\Program Files\Erlang OTP\bin` yourself.

## contributing

Read CONTRIBUTING.md. Short version: zero compiler warnings, tests for
everything public, and nothing gets described in this README before it
has a test.
