# tadpole

A Discord library for Gleam. Every frog starts as a tadpole.

![](assets/tadpole.gif)

Not on Hex yet. See [where this stands](#where-this-stands).

## install

Gleam 1.18+ and Erlang/OTP.

The code on `main` needs 2026.3.0, which is not published. Add it to your
`gleam.toml` as a git dependency until it is:

```toml
[dependencies]
tadpole = { git = "https://github.com/tadpools/tadpole", ref = "main" }
```

Hex carries 2026.2.0, which predates the intent sum type and will not compile
the example below.

Then set the bot token:

    $env:TADPOLE_TOKEN = "your-bot-token"   # PowerShell

## a whole bot

Echoes back every message it sees that did not come from a bot.

Save this as `dev/echo_bot.gleam` in a clone and run it with
`gleam run -m echo_bot`. `dev/` is gitignored because it holds token-driven
scripts, so the copy below is the one to copy. The same program lives at
`test/examples/echo_bot.gleam`, which `gleam test` compiles, so it cannot go
stale the way a listing in prose can.

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

Message Content is a privileged intent. Turn it on in the Developer Portal
under Bot, Privileged Gateway Intents, or drop it from the config. Without
the toggle Discord closes the connection with code 4014 as soon as the bot
identifies. The program prints a reminder before that happens. It cannot
check the portal for you.

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
- **REST.** Read a channel, read history with a cursor, fetch a message,
  send, reply, edit, delete, react, type.

`tadpole/bot` is a thin layer over the same public modules it drives, so
dropping down to `tadpole/rest/execute` or the shard is always available.

## not here yet

Do not assume any of these:

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

That gate has been run by hand and passes: REST authentication, a gateway
connect through READY, and a forced reconnect that comes back RESUMED. It
does not run from CI.

None of the REST routes added in 2026.3.0 has been exercised against real
Discord. They are built from Discord's documented shapes and pinned by
fixtures, which is a weaker claim than having run them.

## running the tests

    gleam test

Three layers, unit, property and contract. TESTING.md is the map, including
how to add to each.

With a token set, the live gate runs too:

    TADPOLE_TOKEN="..." gleam test

Smoke runs are by hand, from `dev/`, which is not in the published tree:

    gleam run -m echo_bot     # the echo bot above
    gleam run -m smoke_gw     # one shard, print events for 60s, exit

Both exit immediately without the token.

Windows: the Erlang installer does not add itself to PATH. Add
`C:\Program Files\Erlang OTP\bin`.

## contributing

CONTRIBUTING.md. Zero compiler warnings, a test for everything public, and
nothing described in this README before it has one.