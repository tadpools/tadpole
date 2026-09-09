# tadpole

A Discord library for Gleam. Every frog starts as a tadpole.

![](assets/tadpole.gif)

## why tadpole

Discord libraries usually grow out of dynamically typed ecosystems, and
their APIs carry the accent. Tadpole starts from Gleam and the BEAM
instead. What that buys, concretely:

- **IDs you cannot mix up.** `UserId`, `GuildId`, `ChannelId`,
  `MessageId` are opaque types (tadpole/types/ids). Passing a `GuildId`
  where a `ChannelId` belongs is a compile error, not a 400 from
  Discord after your bot has been live for a week.

- **Events are Gleam types, not JSON maps.** The handler matches on
  `Ready`, `MessageCreate`, `Resumed`. Real variants, not dict lookups
  (tadpole/gateway/events). Events Tadpole does not recognize
  arrive as `Unknown` with the raw payload attached: a new Discord
  event degrades to one value you can log, never a crash.

- **Errors are data, and they keep secrets.** Every failure is a typed
  variant carrying its context: `RateLimited` has the retry time in
  milliseconds, `RestStatus` has the route, status, and Discord's
  error body.   Match and recover without parsing strings. The opt-in
  renderer prints what happened, why, and what to try, and it redacts
  the token in every path, including paths that only trigger during a
  bug (tadpole/error, tadpole/error/render).

- **The reconnect loop already exists.** The shard is an OTP actor
  that owns its session: heartbeats on Discord's interval with zombie
  detection, per-close-code decisions, resume when the session allows
  it and a clean reidentify when it does not, backoff between attempts
  (tadpole/gateway/shard). A dropped websocket is handled; it is not a
  dead bot you find in the morning.

- **Rate limits are learned, not hardcoded.** Buckets, remaining
  counts, and retry times come from Discord's response headers and 429
  bodies at runtime (tadpole/rest/rate_limit). Discord reshuffles
  buckets without notice; a hardcoded table rots, so there isn't one.

- **The beginner API is not a cage.** `bot.run` is a thin layer over
  the same public modules it drives; it calls `shard.start` exactly
  the way you would (tadpole/bot). When one config and one handler
  stop being enough, the layer below is already public. No fork, no
  reaching into internals.

Also in the box: endpoint bindings for the first hour of any bot:
`GET /users/@me`, post a message, reply (tadpole/rest/endpoints);
model objects with decoders that report where a payload stopped
matching (tadpole/model); and config validation that redacts the token
even in its own describe output (tadpole.describe_config).

The name is the design constraint. A first bot and a sharded
production bot are supposed to be the same framework at different
stages: no stage requires another, growth is additive, and nothing you
wrote at hello-world gets renamed when you need more. That contract
lives in CONTRIBUTING.md and the versioning policy, and reviewers hold
changes to it.

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

271 tests, all against fixtures. No network in CI.

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
