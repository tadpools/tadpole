//// The live publish gate: the one automated test that touches real
//// Discord, and only on explicit request. Without TADPOLE_TOKEN set it
//// prints a one-line note and passes, so CI and every tokenless
//// `gleam test` run stay offline and deterministic.
////
//// With TADPOLE_TOKEN set, it runs CONTRIBUTING's publish gate end to
//// end and asserts typed results at each step:
////
////     TADPOLE_TOKEN="your bot token" gleam test
////
//// 1. REST: get_current_user over the real network returns the bot's
////    own user (this alone proves the token authenticates)
//// 2. Gateway: bot.start connects, identifies, and the handler sees
////    READY as the typed events.Ready variant, whose user matches the
////    REST user's id (this proves hello, heartbeat arming, identify,
////    and the typed event path through the shard)
//// 3. bot.stop closes the connection
////
//// Token hygiene: the token is read from the environment only, never
//// logged, and never appears in failure messages. A failure names what
//// failed (a 401, a READY timeout) and what to check next.

import gleam/erlang/process
import gleam/int
import gleam/io
import gleeunit/should
import tadpole
import tadpole/bot
import tadpole/error/render
import tadpole/gateway/events
import tadpole/model/user.{type User}
import tadpole/rest
import tadpole/rest/endpoints
import tadpole/types/ids

// READY normally lands in a couple of seconds; generous for a slow
// network, short enough that a dead run does not hang the suite.
const ready_timeout_ms = 20_000

@external(erlang, "tadpole_test_ffi", "get_env")
fn get_env(name: String) -> Result(String, Nil)

pub fn live_publish_gate_test() {
  case get_env("TADPOLE_TOKEN") {
    Error(_) -> {
      io.println(
        "info: live_publish_gate skipped (TADPOLE_TOKEN not set; "
        <> "the suite stays offline)",
      )
      Nil
    }
    Ok(token) -> run_gate(token)
  }
}

fn run_gate(token: String) -> Nil {
  // Step 1: REST proves the token authenticates.
  let client = rest.new_client(token, 10_000, True, 2)
  case endpoints.get_current_user(client) {
    Error(e) -> {
      let message =
        "live gate: GET /users/@me failed: "
        <> render.render_error(e)
        <> " (a 401 usually means the token was reset or mistyped)"
      panic as message
    }
    Ok(me) -> {
      { ids.user_to_string(me.id) != "" } |> should.be_true
      io.println("live gate: authenticated as " <> me.username <> " over REST")

      // Step 2: the gateway proves hello, identify, and the typed event
      // path. The handler forwards every event to a subject this test
      // process owns.
      let ready_subject = process.new_subject()
      let assert Ok(tadbot) =
        bot.start(tadpole.new(token), fn(_tadbot, event) {
          process.send(ready_subject, event)
        })

      case receive_ready(ready_subject) {
        Ok(ready_user) -> {
          ids.user_to_string(ready_user.id)
          |> should.equal(ids.user_to_string(me.id))
          io.println(
            "live gate: READY received for "
            <> ready_user.username
            <> " over the gateway",
          )
        }
        Error(_) -> {
          bot.stop(tadbot)
          let message =
            "live gate: no READY within "
            <> seconds(ready_timeout_ms)
            <> "s (check the token's bot account, its portal status, "
            <> "and network access to gateway.discord.gg)"
          panic as message
        }
      }

      // Step 3: clean close.
      bot.stop(tadbot)
    }
  }
}

fn receive_ready(subject: process.Subject(events.Event)) -> Result(User, Nil) {
  case process.receive(subject, ready_timeout_ms) {
    Ok(events.Ready(ready_user, _)) -> Ok(ready_user)
    Ok(_) -> receive_ready(subject)
    Error(_) -> Error(Nil)
  }
}

fn seconds(ms: Int) -> String {
  int.to_string(ms / 1000)
}
