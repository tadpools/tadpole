//// Endpoint binding tests: request shape, JSON bodies, and typed
//// decoding, all through a synthetic transport. The recorder
//// (tadpole_test_ffi) collects the http requests per test; fixtures are
//// invented, never copied from the live API.

import gleam/http
import gleam/http/request.{type Request}
import gleam/http/response
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import tadpole/error
import tadpole/model/emoji
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

/// The two reaction mutations answer 204 with no body.
fn no_content_transport() -> Transport {
  fn(request) {
    record_request(request)
    Ok(response.Response(status: 204, headers: [], body: ""))
  }
}

// fixtures: invented snowflakes (17-19 digits)

const channel = "742300000000000001"

const message = "124400000000000009"

const message_payload = "{\"id\":\"124400000000000009\",\"channel_id\":\"742300000000000001\",\"author\":{\"id\":\"900000000000000125\",\"username\":\"lilypad_bot\"},\"content\":\"quack\",\"timestamp\":\"2026-09-07T18:00:00.000000+00:00\",\"type\":0}"

const user_payload = "{\"id\":\"900000000000000123\",\"username\":\"lilypad_bot\",\"global_name\":\"Lilypad\",\"avatar\":null,\"bot\":true}"

const channel_payload = "{\"id\":\"742300000000000001\",\"type\":0,\"name\":\"general\",\"guild_id\":\"742300000000000002\",\"topic\":\"General chat\"}"

// Discord returns history newest first, so the array below reads
// backwards in time: 900...126 is the newer of the two.

const older_message = "{\"id\":\"124400000000000009\",\"channel_id\":\"742300000000000001\",\"author\":{\"id\":\"900000000000000125\",\"username\":\"lilypad_bot\"},\"content\":\"older\",\"timestamp\":\"2026-09-07T17:00:00.000000+00:00\",\"type\":0}"

const newer_message = "{\"id\":\"124400000000000010\",\"channel_id\":\"742300000000000001\",\"author\":{\"id\":\"900000000000000125\",\"username\":\"lilypad_bot\"},\"content\":\"newer\",\"timestamp\":\"2026-09-07T18:00:00.000000+00:00\",\"type\":0}"

const history_payload = "[" <> newer_message <> "," <> older_message <> "]"

const reactor_one = "{\"id\":\"900000000000000201\",\"username\":\"quackling\",\"bot\":false}"

const reactor_two = "{\"id\":\"900000000000000202\",\"username\":\"pondweed\",\"bot\":false}"

const reaction_users_payload = "[" <> reactor_one <> "," <> reactor_two <> "]"

fn unicode_emoji() -> emoji.Emoji {
  emoji.Unicode("\u{1F44D}")
}

fn custom_emoji() -> emoji.Emoji {
  let assert Ok(id) = ids.emoji_id("740000000000000001")
  emoji.Custom(name: "lilypad", id: id)
}

// GET /channels/{id}/messages

pub fn get_messages_latest_sends_limit_only_test() {
  reset_recorder()

  let assert Ok(_) =
    endpoints.get_messages_with(
      client(),
      transport("[]"),
      channel_id(channel),
      endpoints.Latest(50),
    )

  let assert [sent] = recorded_requests()
  sent.method |> should.equal(http.Get)
  sent.path |> should.equal("/api/v10/channels/" <> channel <> "/messages")
  sent.query |> should.equal(Some("limit=50"))
}

pub fn get_messages_before_sends_the_anchor_test() {
  reset_recorder()

  let assert Ok(_) =
    endpoints.get_messages_with(
      client(),
      transport("[]"),
      channel_id(channel),
      endpoints.Before(message_id(message), 25),
    )

  let assert [sent] = recorded_requests()
  sent.query |> should.equal(Some("before=" <> message <> "&limit=25"))
}

pub fn get_messages_after_sends_the_anchor_test() {
  reset_recorder()

  let assert Ok(_) =
    endpoints.get_messages_with(
      client(),
      transport("[]"),
      channel_id(channel),
      endpoints.After(message_id(message), 25),
    )

  let assert [sent] = recorded_requests()
  sent.query |> should.equal(Some("after=" <> message <> "&limit=25"))
}

pub fn get_messages_around_sends_the_anchor_test() {
  reset_recorder()

  let assert Ok(_) =
    endpoints.get_messages_with(
      client(),
      transport("[]"),
      channel_id(channel),
      endpoints.Around(message_id(message), 5),
    )

  let assert [sent] = recorded_requests()
  sent.query |> should.equal(Some("around=" <> message <> "&limit=5"))
}

pub fn get_messages_clamps_the_limit_to_discords_range_test() {
  // The docs put limit at 1-100 and answer 400 outside that, so an
  // out-of-range number is clamped rather than forwarded.
  reset_recorder()

  let assert Ok(_) =
    endpoints.get_messages_with(
      client(),
      transport("[]"),
      channel_id(channel),
      endpoints.Latest(0),
    )
  let assert [first] = recorded_requests()
  first.query |> should.equal(Some("limit=1"))

  reset_recorder()

  let assert Ok(_) =
    endpoints.get_messages_with(
      client(),
      transport("[]"),
      channel_id(channel),
      endpoints.Latest(-5),
    )
  let assert [second] = recorded_requests()
  second.query |> should.equal(Some("limit=1"))

  reset_recorder()

  let assert Ok(_) =
    endpoints.get_messages_with(
      client(),
      transport("[]"),
      channel_id(channel),
      endpoints.Latest(5000),
    )
  let assert [third] = recorded_requests()
  third.query |> should.equal(Some("limit=100"))
}

pub fn get_messages_keeps_the_query_out_of_the_path_test() {
  // The rate-limit key is built from the path alone, so a query must
  // not leak into it or reads that differ only in limit would stop
  // sharing a bucket.
  reset_recorder()

  let assert Ok(_) =
    endpoints.get_messages_with(
      client(),
      transport("[]"),
      channel_id(channel),
      endpoints.Before(message_id(message), 25),
    )

  let assert [sent] = recorded_requests()
  { string.contains(sent.path, "?") } |> should.be_false
  { string.contains(sent.path, "limit") } |> should.be_false
}

pub fn get_messages_returns_discords_order_with_the_oldest_as_cursor_test() {
  reset_recorder()

  let assert Ok(page) =
    endpoints.get_messages_with(
      client(),
      transport(history_payload),
      channel_id(channel),
      endpoints.Latest(2),
    )

  // Discord sends newest first, and the page keeps that order rather
  // than reversing it behind the caller's back.
  let assert [first, second] = page.messages
  first.content |> should.equal("newer")
  second.content |> should.equal("older")

  // The cursor for the next page back is the oldest, the last element.
  let assert Ok(oldest) = ids.message_id("124400000000000009")
  page.oldest |> should.equal(Some(oldest))
}

pub fn get_messages_empty_array_is_not_an_error_test() {
  // Discord answers 200 with [] when the bot lacks Read Message
  // History, so an empty page is a normal result, not a failure.
  reset_recorder()

  let assert Ok(page) =
    endpoints.get_messages_with(
      client(),
      transport("[]"),
      channel_id(channel),
      endpoints.Latest(50),
    )

  page.messages |> should.equal([])
  page.oldest |> should.equal(None)
}

pub fn get_messages_forbidden_maps_to_rest_status_test() {
  reset_recorder()

  let assert Error(error.RestStatus(route, 403, _, _)) =
    endpoints.get_messages_with(
      client(),
      fn(request) {
        record_request(request)
        Ok(response.Response(status: 403, headers: [], body: "{}"))
      },
      channel_id(channel),
      endpoints.Latest(50),
    )

  error.route_to_string(route)
  |> should.equal("GET /channels/" <> channel <> "/messages")
}

pub fn get_messages_non_array_body_maps_to_decode_failed_test() {
  reset_recorder()

  let assert Error(error.DecodeFailed(_, path, _, _)) =
    endpoints.get_messages_with(
      client(),
      transport("{\"not\":\"an array\"}"),
      channel_id(channel),
      endpoints.Latest(50),
    )

  path |> should.equal("$")
}

pub fn get_messages_default_limit_is_discords_documented_default_test() {
  endpoints.default_history_limit |> should.equal(50)
}

// POST /channels/{id}/typing

pub fn set_typing_posts_to_the_typing_route_test() {
  reset_recorder()

  let assert Ok(Nil) =
    endpoints.set_typing_with(
      client(),
      no_content_transport(),
      channel_id(channel),
    )

  let assert [sent] = recorded_requests()
  sent.method |> should.equal(http.Post)
  sent.path |> should.equal("/api/v10/channels/" <> channel <> "/typing")
  // The route takes no JSON params, so the body is empty and there is no
  // query to keep out of the rate-limit key.
  sent.body |> should.equal("")
  sent.query |> should.equal(None)
}

pub fn set_typing_forbidden_maps_to_rest_status_test() {
  reset_recorder()

  let assert Error(error.RestStatus(route, 403, Some(50_013), _)) =
    endpoints.set_typing_with(
      client(),
      fn(request) {
        record_request(request)
        Ok(response.Response(
          status: 403,
          headers: [],
          body: "{\"message\": \"Missing Permissions\", \"code\": 50013}",
        ))
      },
      channel_id(channel),
    )

  error.route_to_string(route)
  |> should.equal("POST /channels/" <> channel <> "/typing")
}

// PUT /channels/{id}/messages/{id}/reactions/{emoji}/@me

pub fn add_reaction_puts_an_encoded_unicode_emoji_test() {
  reset_recorder()

  let assert Ok(Nil) =
    endpoints.add_reaction_with(
      client(),
      no_content_transport(),
      channel_id(channel),
      message_id(message),
      unicode_emoji(),
    )

  let assert [sent] = recorded_requests()
  sent.method |> should.equal(http.Put)
  // %F0%9F%91%8D is \u{1F44D}. Unencoded, Discord answers 10014.
  sent.path
  |> should.equal(
    "/api/v10/channels/"
    <> channel
    <> "/messages/"
    <> message
    <> "/reactions/%F0%9F%91%8D/@me",
  )
}

pub fn add_reaction_puts_a_custom_emoji_as_name_id_test() {
  reset_recorder()

  let assert Ok(Nil) =
    endpoints.add_reaction_with(
      client(),
      no_content_transport(),
      channel_id(channel),
      message_id(message),
      custom_emoji(),
    )

  let assert [sent] = recorded_requests()
  sent.path
  |> should.equal(
    "/api/v10/channels/"
    <> channel
    <> "/messages/"
    <> message
    <> "/reactions/lilypad%3A740000000000000001/@me",
  )
}

// DELETE /channels/{id}/messages/{id}/reactions/{emoji}/@me

pub fn remove_own_reaction_deletes_the_encoded_emoji_test() {
  reset_recorder()

  let assert Ok(Nil) =
    endpoints.remove_own_reaction_with(
      client(),
      no_content_transport(),
      channel_id(channel),
      message_id(message),
      custom_emoji(),
    )

  let assert [sent] = recorded_requests()
  sent.method |> should.equal(http.Delete)
  sent.path
  |> should.equal(
    "/api/v10/channels/"
    <> channel
    <> "/messages/"
    <> message
    <> "/reactions/lilypad%3A740000000000000001/@me",
  )
}

// GET /channels/{id}/messages/{id}/reactions/{emoji}

pub fn get_reaction_users_lists_users_with_a_limit_test() {
  reset_recorder()

  let assert Ok(_) =
    endpoints.get_reaction_users_with(
      client(),
      transport(reaction_users_payload),
      channel_id(channel),
      message_id(message),
      unicode_emoji(),
      None,
      25,
    )

  let assert [sent] = recorded_requests()
  sent.method |> should.equal(http.Get)
  sent.path
  |> should.equal(
    "/api/v10/channels/"
    <> channel
    <> "/messages/"
    <> message
    <> "/reactions/%F0%9F%91%8D",
  )
  sent.query |> should.equal(Some("limit=25"))
}

pub fn get_reaction_users_sends_after_when_paging_test() {
  reset_recorder()
  let assert Ok(after) = ids.user_id("900000000000000201")

  let assert Ok(_) =
    endpoints.get_reaction_users_with(
      client(),
      transport("[]"),
      channel_id(channel),
      message_id(message),
      unicode_emoji(),
      Some(after),
      100,
    )

  let assert [sent] = recorded_requests()
  sent.query
  |> should.equal(Some("after=900000000000000201&limit=100"))
}

pub fn get_reaction_users_clamps_the_limit_test() {
  reset_recorder()

  let assert Ok(_) =
    endpoints.get_reaction_users_with(
      client(),
      transport("[]"),
      channel_id(channel),
      message_id(message),
      unicode_emoji(),
      None,
      5000,
    )

  let assert [sent] = recorded_requests()
  sent.query |> should.equal(Some("limit=100"))
}

pub fn get_reaction_users_returns_the_last_user_as_the_cursor_test() {
  reset_recorder()

  let assert Ok(page) =
    endpoints.get_reaction_users_with(
      client(),
      transport(reaction_users_payload),
      channel_id(channel),
      message_id(message),
      unicode_emoji(),
      None,
      25,
    )

  let assert [first, second] = page.users
  first.username |> should.equal("quackling")
  second.username |> should.equal("pondweed")

  let assert Ok(after) = ids.user_id("900000000000000202")
  page.next_after |> should.equal(Some(after))
}

pub fn get_reaction_users_empty_list_has_no_cursor_test() {
  reset_recorder()

  let assert Ok(page) =
    endpoints.get_reaction_users_with(
      client(),
      transport("[]"),
      channel_id(channel),
      message_id(message),
      unicode_emoji(),
      None,
      25,
    )

  page.users |> should.equal([])
  page.next_after |> should.equal(None)
}

pub fn get_reaction_users_not_found_maps_to_rest_status_test() {
  // "Nobody has reacted with that emoji" is a 404 from Discord, not an
  // empty list, so the error path is the common one here.
  reset_recorder()

  let assert Error(error.RestStatus(route, 404, Some(10_008), _)) =
    endpoints.get_reaction_users_with(
      client(),
      fn(request) {
        record_request(request)
        Ok(response.Response(
          status: 404,
          headers: [],
          body: "{\"message\": \"Unknown Message\", \"code\": 10008}",
        ))
      },
      channel_id(channel),
      message_id(message),
      unicode_emoji(),
      None,
      25,
    )

  string.contains(error.route_to_string(route), "/reactions/")
  |> should.be_true
}

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

// GET /channels/{id}

pub fn get_channel_sends_get_channels_id_test() {
  reset_recorder()

  let assert Ok(ch) =
    endpoints.get_channel_with(
      client(),
      transport(channel_payload),
      channel_id(channel),
    )

  let assert [sent] = recorded_requests()
  sent.method |> should.equal(http.Get)
  sent.path |> should.equal("/api/v10/channels/" <> channel)
  ch.name |> should.equal(Some("general"))
}

// GET /channels/{id}/messages/{id}

pub fn get_message_sends_get_test() {
  reset_recorder()

  let assert Ok(msg) =
    endpoints.get_message_with(
      client(),
      transport(message_payload),
      channel_id(channel),
      message_id(message),
    )

  let assert [sent] = recorded_requests()
  sent.method |> should.equal(http.Get)
  sent.path
  |> should.equal("/api/v10/channels/" <> channel <> "/messages/" <> message)
  msg.content |> should.equal("quack")
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

// PATCH /channels/{id}/messages/{id}

pub fn edit_message_sends_patch_test() {
  reset_recorder()

  let edited_payload =
    "{\"id\":\""
    <> message
    <> "\",\"channel_id\":\""
    <> channel
    <> "\",\"author\":{\"id\":\"900000000000000125\",\"username\":\"lilypad_bot\"},\"content\":\"edited\",\"timestamp\":\"2026-09-07T18:00:00.000000+00:00\",\"edited_timestamp\":\"2026-09-07T18:01:00.000000+00:00\",\"type\":0}"

  let assert Ok(edited) =
    endpoints.edit_message_with(
      client(),
      transport(edited_payload),
      channel_id(channel),
      message_id(message),
      "edited",
    )

  let assert [sent] = recorded_requests()
  sent.method |> should.equal(http.Patch)
  sent.path
  |> should.equal("/api/v10/channels/" <> channel <> "/messages/" <> message)
  sent.body |> should.equal("{\"content\":\"edited\"}")
  edited.content |> should.equal("edited")
}

// DELETE /channels/{id}/messages/{id}

pub fn delete_message_sends_delete_test() {
  reset_recorder()

  // Discord returns 204 No Content for deletes; empty body.
  let assert Ok(Nil) =
    endpoints.delete_message_with(
      client(),
      fn(request) {
        record_request(request)
        Ok(response.Response(status: 204, headers: [], body: ""))
      },
      channel_id(channel),
      message_id(message),
    )

  let assert [sent] = recorded_requests()
  sent.method |> should.equal(http.Delete)
  sent.path
  |> should.equal("/api/v10/channels/" <> channel <> "/messages/" <> message)
  sent.body |> should.equal("")
}

pub fn delete_message_forbidden_passes_through_test() {
  reset_recorder()
  let body = "{\"message\": \"Missing Permissions\", \"code\": 50013}"

  let assert Error(error.RestStatus(route, 403, _, _)) =
    endpoints.delete_message_with(
      client(),
      fn(request) {
        record_request(request)
        Ok(response.Response(status: 403, headers: [], body: body))
      },
      channel_id(channel),
      message_id(message),
    )

  error.route_to_string(route)
  |> should.equal("DELETE /channels/" <> channel <> "/messages/" <> message)
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
