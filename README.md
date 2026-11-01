# tadpole

A Discord library for Gleam. Every frog starts as a tadpole.

![](assets/tadpole.gif)

Tadpole isn't on Hex yet. See [where this stands](#where-this-stands).

## install

Gleam 1.18+ and Erlang/OTP.

The `main` branch uses 2026.3.0, which hasn't been published yet. Until then,
add Tadpole as a Git dependency in `gleam.toml`:

```toml
[dependencies]
tadpole = { git = "https://github.com/tadpools/tadpole", ref = "main" }
```

Hex still has 2026.2.0. It predates the intent sum type, so the example below
won't compile against that release.

Then set the bot token:

    $env:TADPOLE_TOKEN = "your-bot-token"   # PowerShell

## a whole bot

Echoes each non-empty message it receives unless the author is a bot.

Save this as `dev/echo_bot.gleam` in a clone and run it with
`gleam run -m echo_bot`. The `dev/` directory is gitignored because it holds
token-driven scripts. The same program lives in
`test/examples/echo_bot.gleam`, where `gleam test` compiles it; a test also
checks that this README listing stays in sync.

```gleam
import gleam/io
import gleam/list
import gleam/string
import tadpole
import tadpole/bot
import tadpole/error/render
import tadpole/gateway/events.{type Event, MessageCreate, Ready}
import tadpole/intent
import tadpole/model/message.{type Message}

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
      |> intent.enable(intent.Guilds)
      |> intent.enable(intent.GuildMessages)
      |> intent.enable(intent.MessageContent),
    )

  // Message Content is privileged. Without the portal toggle Discord
  // closes with code 4014 the moment we identify.
  case tadpole.privileged_intents_requested(cfg) {
    [] -> Nil
    privileged ->
      io.println(
        "echo_bot: this config requests privileged intents ("
        <> join_names(privileged)
        <> "). Enable them in the Discord Developer Portal, Bot, "
        <> "Privileged Gateway Intents, or the gateway closes the "
        <> "connection with code 4014.",
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
      // Echoing our own messages would loop forever. Empty content is an
      // embed-only post, which a text reply cannot echo.
      case message.author.bot, message.content {
        True, _ -> Nil
        False, "" -> Nil
        False, content -> reply(tadbot, message, content)
      }

    _ -> Nil
  }
}

fn reply(tadbot: bot.Bot, message: Message, content: String) -> Nil {
  case bot.reply(tadbot, message.channel_id, message.id, content) {
    Ok(_) -> Nil
    Error(e) -> io.println(render.render_error(e))
  }
}

fn join_names(names: List(intent.Intent)) -> String {
  names
  |> list.map(intent.intent_name)
  |> string.join(", ")
}

@external(erlang, "tadpole_ffi", "get_env")
fn env(name: String) -> Result(String, Nil)
```

Message Content is a privileged intent. Enable it in the Developer Portal
under Bot → Privileged Gateway Intents, or remove it from the config. If the
toggle is off, Discord closes the gateway connection with code 4014 when the
bot identifies. The example warns you before connecting, but it can't check
the portal setting itself.

## what is here

- **Opaque IDs.** One type per Discord object, so the wrong one is a
  compile error and not a 400 from Discord.
- **Typed events.** Match on `Ready`, `MessageCreate` and the rest. An
  event the library does not model arrives as `Unknown` with the raw
  payload, so it is data you can log.
- **Typed errors.** `RateLimited` carries the retry window, `RestStatus`
  carries the route and Discord's error body. `tadpole/error/render` prints
  what happened and redacts the token.
- **Reconnection you do not have to write.** The shard actor heartbeats on
  Discord's interval, notices a zombie connection, decides per close code
  whether to resume or identify fresh, and backs off between attempts.
- **Rate limits read at runtime.** Buckets, remaining counts and retry
  windows come from response headers and 429 bodies. No hardcoded table.
- **REST calls.** Read a channel, page through its message history, fetch a
  message, inspect computed guild or channel permissions, and send, reply,
  edit, delete, react, or show a typing indicator.

`tadpole/bot` is a thin layer over the same public modules it drives, so
dropping down to `tadpole/rest/execute` or the shard is always available.

## not here yet

These features aren't in this version yet:

- multi-shard. One shard. A config asking for more is refused with
  `ShardingNotSupported` before anything connects.
- interactions and slash commands
- embeds, file uploads, message components
- voice
- a cache. Every event is what Discord just sent. Nothing is remembered.
- member lists or presence beyond what rides along in other payloads
- graceful shutdown. `bot.stop` closes the gateway and the program ends the
  usual way.

## where this stands

Everything is tested against recorded payloads and canned HTTP responses.
The one test that touches real Discord is gated on `TADPOLE_TOKEN`, so CI
needs no secret and never sees a network.

The live gate has passed manual runs for REST authentication, a gateway
connection through READY, and a forced reconnect that returned RESUMED. It
doesn't run in CI.

The REST routes added in 2026.3.0 haven't yet been exercised against live
Discord. They're based on Discord's documented payloads and covered by
fixtures, which is useful but not the same as a live run.

## running the tests

    gleam test

The suite has unit, property, and contract tests. TESTING.md explains what
each layer covers and how to add to it.

With a token set, the live gate runs too:

    TADPOLE_TOKEN="..." gleam test

For manual smoke runs, use the scripts in the gitignored `dev/` directory:

    gleam run -m echo_bot     # the echo bot above
    gleam run -m smoke_gw     # one shard, print events for 60s, exit

Both exit immediately without the token.

Windows: the Erlang installer does not add itself to PATH. Add
`C:\Program Files\Erlang OTP\bin`.

## contributing

For contribution rules, see CONTRIBUTING.md. CI requires zero compiler
warnings, tests for public functions, and README claims backed by working
code.
