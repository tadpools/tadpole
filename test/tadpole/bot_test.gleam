//// Offline tests for the bot runner. Everything here avoids the network:
//// startup rejection paths fail before any process is spawned, REST
//// delegation runs over the recorded synthetic transport, and stop is
//// checked against a subject the test process owns. The dispatcher loop
//// itself only lives once a real shard starts, so its sequential
//// delivery is documented behavior, not tested here.

import gleam/erlang/process
import gleam/http
import gleam/http/request.{type Request}
import gleam/http/response
import gleam/option.{Some}
import gleam/string
import gleeunit/should
import tadpole
import tadpole/bot
import tadpole/error
import tadpole/error/render
import tadpole/gateway/events
import tadpole/gateway/shard
import tadpole/rest
import tadpole/rest/execute.{type Transport}
import tadpole/types/ids

@external(erlang, "tadpole_test_ffi", "record_request")
fn record_request(request: Request(String)) -> Nil

@external(erlang, "tadpole_test_ffi", "requests")
fn recorded_requests() -> List(Request(String))

@external(erlang, "tadpole_test_ffi", "reset")
fn reset_recorder() -> Nil

// Long enough to pass tadpole.validate (>= 50 chars, no whitespace).
const fake_token = "faketoken_faketoken_faketoken_faketoken_faketoken_1"

// fixtures: invented snowflakes, same shape as the rest/endpoints tests.

const channel = "742300000000000001"

const message = "124400000000000009"

const message_payload = "{\"id\":\"124400000000000009\",\"channel_id\":\"742300000000000001\",\"author\":{\"id\":\"900000000000000125\",\"username\":\"lilypad_bot\"},\"content\":\"quack\",\"timestamp\":\"2026-09-07T18:00:00.000000+00:00\",\"type\":0}"

fn no_op(_bot: bot.Bot, _event: events.Event) -> Nil {
  Nil
}

fn transport_ok(body: String) -> Transport {
  fn(request) {
    record_request(request)
    Ok(response.Response(status: 200, headers: [], body: body))
  }
}

/// A Bot built by hand, exactly as a test would need one: no shard
/// started, transport injected.
fn hand_built_bot(t: Transport) -> bot.Bot {
  bot.Bot(
    config: tadpole.new(fake_token),
    rest: rest.new_client(fake_token, 5000, True, 2),
    shard: process.new_subject(),
    token: fake_token,
    transport: t,
  )
}

fn channel_id(value: String) -> ids.ChannelId {
  let assert Ok(id) = ids.channel_id(value)
  id
}

fn message_id(value: String) -> ids.MessageId {
  let assert Ok(id) = ids.message_id(value)
  id
}

// start / run

pub fn start_rejects_missing_token_before_spawning_test() {
  bot.start(tadpole.new(""), no_op) |> should.equal(Error(error.MissingToken))
}

pub fn start_rejects_multi_shard_configs_test() {
  let config = tadpole.new(fake_token) |> tadpole.with_shards(2)

  bot.start(config, no_op)
  |> should.equal(Error(error.ShardingNotSupported(2)))
}

pub fn sharding_error_is_actionable_and_rendered_test() {
  render.severity_of(error.ShardingNotSupported(2))
  |> should.equal(render.Actionable)

  let rendered = render.render_error(error.ShardingNotSupported(4))
  { string.length(rendered) > 0 } |> should.be_true
  string.contains(rendered, "4") |> should.be_true
  string.contains(rendered, "with_shards") |> should.be_true
}

pub fn run_fails_fast_when_config_is_rejected_test() {
  // An empty token must come back as an Error, not park the process.
  bot.run(tadpole.new(""), no_op) |> should.equal(Error(error.MissingToken))
}

// send_message / reply delegation

pub fn send_message_delegates_over_the_bot_transport_test() {
  reset_recorder()

  let assert Ok(sent) =
    bot.send_message(
      hand_built_bot(transport_ok(message_payload)),
      channel_id(channel),
      "quack",
    )

  let assert [sent_request] = recorded_requests()
  sent_request.method |> should.equal(http.Post)
  sent_request.path
  |> should.equal("/api/v10/channels/" <> channel <> "/messages")
  sent_request.body |> should.equal("{\"content\":\"quack\"}")

  sent.content |> should.equal("quack")
  ids.message_to_string(sent.id) |> should.equal(message)
  let assert Ok(sent_channel) = ids.channel_id(channel)
  sent.channel_id |> should.equal(sent_channel)
}

pub fn reply_delegates_with_message_reference_test() {
  reset_recorder()

  let assert Ok(_) =
    bot.reply(
      hand_built_bot(transport_ok(message_payload)),
      channel_id(channel),
      message_id(message),
      "echo",
    )

  let assert [sent_request] = recorded_requests()
  sent_request.body
  |> should.equal(
    "{\"content\":\"echo\",\"message_reference\":{\"message_id\":\""
    <> message
    <> "\"}}",
  )
}

pub fn send_message_passes_rest_errors_through_test() {
  reset_recorder()
  let forbidden = fn(request) {
    record_request(request)
    Ok(response.Response(
      status: 403,
      headers: [],
      body: "{\"message\": \"Missing Permissions\", \"code\": 50013}",
    ))
  }

  let assert Error(error.RestStatus(route, 403, Some(50_013), _)) =
    bot.send_message(hand_built_bot(forbidden), channel_id(channel), "hi")

  error.route_to_string(route)
  |> should.equal("POST /channels/" <> channel <> "/messages")
}

// stop

pub fn stop_signals_the_shard_test() {
  let shard_subject = process.new_subject()
  let running =
    bot.Bot(..hand_built_bot(transport_ok("")), shard: shard_subject)

  bot.stop(running)

  let assert Ok(shard.Stop) = process.receive(shard_subject, 100)
  Nil
}
