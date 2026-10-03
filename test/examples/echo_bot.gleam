//// The echo bot from README.md, compiled but not run.
////
//// README.md shows this program and says it is the copy to copy. It
//// used to live only there, and drifted: when intents became a sum type
//// in 2026.3.0 the README kept the old lowercase names and the example
//// stopped compiling, with nothing to notice it. Keeping the canonical
//// program here means `gleam test` compiles it, and
//// test/tadpole/readme_test.gleam compares this file against the fenced
//// block in README.md so the two cannot drift apart either.
////
//// It is a module without a `_test` suffix, so gleeunit compiles it and
//// does not run it. Save it as dev/echo_bot.gleam to run it for real:
//// dev/ is gitignored because it holds token-driven scripts.

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
