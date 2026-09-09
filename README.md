# tadpole

A Discord library for Gleam. Every frog starts as a tadpole.

![](assets/tadpole.gif)

## where this actually is

The first vertical slice works. A bot can connect to Discord's gateway,
identify, heartbeat, resume after a disconnect, and receive typed events.
REST calls run over gleam_httpc with rate-limit handling learned from
response headers. The echo bot below is a complete program.

Not here yet — do not assume it:

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
from CI, and the package is not on Hex yet — the publish gate in
CONTRIBUTING.md requires one live roundtrip (gateway connect through
ready, plus one real REST call) first, and that check has not happened
yet. Adjust trust accordingly.

## what you get

- typed events: `Ready`, `MessageCreate`, `MessageUpdate`, `MessageDelete`,
  `Resumed`, `GuildCreate`, `GuildDelete`. Anything else arrives as
  `Unknown` with the raw payload attached, never a crash
  (tadpole/gateway/events).
- the beginner runner: `start`, `run`, `send_message`, `reply`, `stop`.
  One config, one handler. Events reach the handler one at a time in
  arrival order — a slow handler delays the queue behind it, and a
  handler crash takes the bot down instead of leaving it silently dead
  (tadpole/bot).
- a gateway shard that connects, heartbeats on Discord's interval,
  identifies or resumes, decides per close code, and reconnects with
  backoff (tadpole/gateway/shard, tadpole/gateway/transport).
- REST execution with an injectable transport — gleam_httpc ships as the
  default — and 429 retries (tadpole/rest/execute).
- rate limits taken from response headers and 429 bodies only. No
  hardcoded table: Discord reshuffles buckets without notice
  (tadpole/rest/rate_limit).
- endpoint bindings for the first hour of any bot: `GET /users/@me`,
  post a message, reply (tadpole/rest/endpoints).
- model objects — user, message (full and the partial MESSAGE_UPDATE
  form), guild, channel — with decoders that report where a payload
  stopped matching (tadpole/model).
- opaque IDs, so a `UserId` cannot be passed where a `GuildId` goes
  (tadpole/types/ids).
- a typed error type rendered for humans, with the token redacted
  everywhere it might show up (tadpole/error, tadpole/error/render).

## a whole bot

Gleam 1.18+ and Erlang/OTP.

    gleam add tadpole        # works once the live check below has passed
    $env:TADPOLE_TOKEN = "your-bot-token"   # PowerShell

This is dev/echo_bot.gleam from the repo — the repo copy is the one kept
in sync. The `env` helper at the bottom is the only Erlang in the
program; tadpole ships it, though it is private and allowed to move.

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

    gleam run -m echo_bot

Message Content is a privileged intent. Enable it in the Discord
Developer Portal (Bot → Privileged Gateway Intents) or drop it from the
config. Without the toggle, Discord hangs up with close code 4014 the
moment the bot identifies. The example prints a reminder before that
happens; it cannot check the portal for you.

## running the tests

    gleam test

271 tests, all against fixtures. No network in CI.

Smoke runs against real Discord, by hand, with a token in
`TADPOLE_TOKEN` — both exit immediately without it:

    gleam run -m echo_bot     # the echo bot: repeats non-bot messages
    gleam run -m smoke_gw     # connects one shard, prints events for 60s, exits

Windows note: the Erlang installer doesn't add itself to PATH. Add
`C:\Program Files\Erlang OTP\bin` yourself.

## why "tadpole"

Small bots should be able to grow without a rewrite. The mascot is a
tadpole. That's the whole story.

## contributing

Read CONTRIBUTING.md. Short version: zero compiler warnings, tests for
everything public, and nothing gets described in this README before it
has a test.
