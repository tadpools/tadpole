//// Endpoint binding tests: request shape, JSON bodies, and typed
//// decoding, all through a synthetic transport. The recorder
//// (tadpole_test_ffi) collects the http requests per test; fixtures are
//// invented, never copied from the live API.

import gleam/http
import gleam/http/request.{type Request}
import gleam/http/response
import gleam/option.{Some}
import gleeunit/should
import tadpole/error
import tadpole/rest
import tadpole/rest/endpoints
import tadpole/rest/execute.{type Transport}
import tadpole/types/ids

@external(erlang, "tadpole_test_ffi", "record_request")
fn record_request(request: Request(String)) -> Nil

@external(erlang, "tadpole_test_ffi", "requests")
fn recorded_requests() -> List(Request(String))

@external(erlang, "tadpole_test_ffi", "reset")
fn reset_recorder() -> Nil

const token = "faketoken_faketoken_faketoken_1234"

fn client() -> rest.RestClient {
  rest.new_client(token, 5000, True, 2)
}

fn transport(body: String) -> Transport {
  fn(request) {
    record_request(request)
    Ok(response.Response(status: 200, headers: [], body: body))
  }
}

// fixtures: invented snowflakes (17-19 digits)

const channel = "742300000000000001"

const message = "124400000000000009"

const message_payload = "{\"id\":\"124400000000000009\",\"channel_id\":\"742300000000000001\",\"author\":{\"id\":\"900000000000000125\",\"username\":\"lilypad_bot\"},\"content\":\"quack\",\"timestamp\":\"2026-09-07T18:00:00.000000+00:00\",\"type\":0}"

const user_payload = "{\"id\":\"900000000000000123\",\"username\":\"lilypad_bot\",\"global_name\":\"Lilypad\",\"avatar\":null,\"bot\":true}"

// GET /users/@me

pub fn get_current_user_sends_get_users_at_me_test() {
  reset_recorder()

  let assert Ok(bot) =
    endpoints.get_current_user_with(client(), transport(user_payload))

  let assert [sent] = recorded_requests()
  sent.method |> should.equal(http.Get)
  sent.path |> should.equal("/api/v10/users/@me")
  rest.header(sent.headers, "authorization")
  |> should.equal(Some("Bot " <> token))
  bot.username |> should.equal("lilypad_bot")
  bot.global_name |> should.equal(Some("Lilypad"))
  bot.bot |> should.equal(True)
}

// POST /channels/{id}/messages

pub fn send_message_posts_json_body_test() {
  reset_recorder()

  let assert Ok(sent_message) =
    endpoints.send_message_with(
      client(),
      transport(message_payload),
      channel_id(channel),
      "quack",
    )

  let assert [sent] = recorded_requests()
  sent.method |> should.equal(http.Post)
  sent.path
  |> should.equal("/api/v10/channels/" <> channel <> "/messages")
  rest.header(sent.headers, "content-type")
  |> should.equal(Some("application/json"))
  sent.body |> should.equal("{\"content\":\"quack\"}")

  ids.message_to_string(sent_message.id) |> should.equal(message)
  sent_message.content |> should.equal("quack")
  let assert Ok(author_channel) = ids.channel_id(channel)
  sent_message.channel_id |> should.equal(author_channel)
}

pub fn reply_adds_message_reference_test() {
  reset_recorder()

  let assert Ok(_) =
    endpoints.reply_with(
      client(),
      transport(message_payload),
      channel_id(channel),
      message_id(message),
      "replying",
    )

  let assert [sent] = recorded_requests()
  sent.body
  |> should.equal(
    "{\"content\":\"replying\",\"message_reference\":{\"message_id\":\""
    <> message
    <> "\"}}",
  )
}

// errors pass through untouched

pub fn unauthorized_maps_to_rest_status_test() {
  reset_recorder()
  let body = "{\"message\": \"Invalid authentication token\", \"code\": 0}"

  let assert Error(error.RestStatus(route, 401, Some(0), Some(stored))) =
    endpoints.get_current_user_with(client(), fn(req) {
      record_request(req)
      Ok(response.Response(status: 401, headers: [], body: body))
    })

  error.route_to_string(route) |> should.equal("GET /users/@me")
  stored |> should.equal(body)
}

pub fn malformed_success_body_maps_to_decode_failed_test() {
  reset_recorder()

  let assert Error(error.DecodeFailed(_, path, _, _)) =
    endpoints.get_current_user_with(client(), transport("not json at all"))

  path |> should.equal("$")
}

// helpers

fn channel_id(value: String) -> ids.ChannelId {
  let assert Ok(id) = ids.channel_id(value)
  id
}

fn message_id(value: String) -> ids.MessageId {
  let assert Ok(id) = ids.message_id(value)
  id
}
