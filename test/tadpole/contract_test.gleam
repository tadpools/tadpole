//// Contract tests: the fixture files under test/fixtures are the
//// payload corpus, decoded here by the production decoders exactly the
//// way the wiring calls them. Each test is named after the fixture it
//// loads, so a failure points straight at the payload.
////
//// Gateway fixtures carry the full dispatch envelope (t, s, op, d)
//// because that is what frame.parse produces and what the shard hands
//// to events.decode; these tests drive that same pair. The rate limit
//// fixture carries the headers a 429 response reports and the body
//// Discord documents for it.

import gleam/dict
import gleam/dynamic/decode as d
import gleam/int
import gleam/json
import gleam/option.{None, Some}
import gleeunit/should
import tadpole/error
import tadpole/gateway/events
import tadpole/gateway/frame
import tadpole/gateway/opcode
import tadpole/rest.{RestResponse}
import tadpole/rest/rate_limit
import tadpole/support/fixtures
import tadpole/types/ids

pub fn fixture_ready_minimal_decodes_test() {
  let payload = fixtures.must_load("ready_minimal.json")
  let assert Ok(frame) = frame.parse(payload)
  frame.opcode |> should.equal(opcode.Dispatch)

  let assert Ok(events.Ready(user, guild_count)) =
    events.decode("READY", frame.raw)
  user.username |> should.equal("pond_bot")
  user.bot |> should.be_true
  guild_count |> should.equal(0)
}

pub fn fixture_ready_full_decodes_test() {
  let payload = fixtures.must_load("ready_full.json")
  let assert Ok(frame) = frame.parse(payload)

  let assert Ok(events.Ready(user, guild_count)) =
    events.decode("READY", frame.raw)
  user.bot |> should.be_true
  guild_count |> should.equal(2)
}

pub fn fixture_message_create_minimal_decodes_test() {
  let payload = fixtures.must_load("message_create_minimal.json")
  let assert Ok(frame) = frame.parse(payload)

  let assert Ok(events.MessageCreate(message)) =
    events.decode("MESSAGE_CREATE", frame.raw)
  message.content |> should.equal("hello pond")
  message.guild_id |> should.equal(None)
  message.tts |> should.be_false
  ids.channel_to_string(message.channel_id)
  |> should.equal("400000000000000001")
}

pub fn fixture_message_create_full_decodes_test() {
  let payload = fixtures.must_load("message_create_full.json")
  let assert Ok(frame) = frame.parse(payload)

  let assert Ok(events.MessageCreate(message)) =
    events.decode("MESSAGE_CREATE", frame.raw)
  message.content |> should.equal("full pond message")
  let assert [mention] = message.mentions
  mention.username |> should.equal("pond_bot")
  message.mention_role_ids |> should.equal([role_a(), role_b()])
  let assert [attachment] = message.attachments
  attachment.filename |> should.equal("lilypad.png")
  message.webhook_id |> should.equal(None)
  let assert Some(edited) = message.edited_timestamp
  edited |> should.equal("2026-09-09T12:02:00.000000+00:00")
}

fn role_a() -> ids.RoleId {
  let assert Ok(id) = ids.role_id("500000000000000001")
  id
}

fn role_b() -> ids.RoleId {
  let assert Ok(id) = ids.role_id("500000000000000002")
  id
}

pub fn fixture_message_create_bad_id_fails_at_the_field_test() {
  let payload = fixtures.must_load("message_create_bad_id.json")
  let assert Ok(frame) = frame.parse(payload)

  let assert Error(error.DecodeFailed(_, path, expected, got)) =
    events.decode("MESSAGE_CREATE", frame.raw)
  path |> should.equal("author.id")
  expected |> should.equal("a Discord snowflake string")
  got |> should.equal("not-a-snowflake")
}

pub fn fixture_message_update_partial_decodes_test() {
  let payload = fixtures.must_load("message_update_partial.json")
  let assert Ok(frame) = frame.parse(payload)

  let assert Ok(events.MessageUpdate(update)) =
    events.decode("MESSAGE_UPDATE", frame.raw)
  update.content |> should.equal(Some("edited pond message"))
  update.author |> should.equal(None)
  update.pinned |> should.equal(Some(True))
}

pub fn fixture_message_delete_minimal_decodes_test() {
  let payload = fixtures.must_load("message_delete_minimal.json")
  let assert Ok(frame) = frame.parse(payload)

  let assert Ok(events.MessageDelete(id, channel_id, guild_id)) =
    events.decode("MESSAGE_DELETE", frame.raw)
  ids.message_to_string(id) |> should.equal("110000000000000003")
  ids.channel_to_string(channel_id) |> should.equal("400000000000000001")
  let assert Some(guild) = guild_id
  ids.guild_to_string(guild) |> should.equal("300000000000000001")
}

pub fn fixture_guild_create_minimal_decodes_test() {
  let payload = fixtures.must_load("guild_create_minimal.json")
  let assert Ok(frame) = frame.parse(payload)

  let assert Ok(events.GuildCreate(guild)) =
    events.decode("GUILD_CREATE", frame.raw)
  guild.name |> should.equal("The Pond")
  guild.member_count |> should.equal(Some(42))
}

pub fn fixture_guild_delete_unavailable_decodes_test() {
  let payload = fixtures.must_load("guild_delete_unavailable.json")
  let assert Ok(frame) = frame.parse(payload)

  let assert Ok(events.GuildDelete(unavailable)) =
    events.decode("GUILD_DELETE", frame.raw)
  ids.guild_to_string(unavailable.id) |> should.equal("300000000000000001")
}

pub fn fixture_unknown_field_added_survives_test() {
  let payload = fixtures.must_load("unknown_field_added.json")
  let assert Ok(frame) = frame.parse(payload)

  // Discord adding fields tomorrow must not break today's decoder.
  let assert Ok(events.MessageCreate(message)) =
    events.decode("MESSAGE_CREATE", frame.raw)
  message.content
  |> should.equal("a field Discord has not shipped yet must not break decoding")
}

pub fn fixture_hello_null_fields_parses_test() {
  // The first frame every real connection receives, exactly as Discord
  // sends it: t and s are null, not absent. This shape once failed the
  // parse and the whole connection sat deaf; see the module docs on
  // frame.parse.
  let payload = fixtures.must_load("hello_null_fields.json")
  let assert Ok(frame) = frame.parse(payload)
  frame.opcode |> should.equal(opcode.Hello)
  frame.sequence |> should.equal(None)
  frame.event_name |> should.equal(None)

  // The shard reads the interval straight from this frame.
  let assert Ok(interval) = frame.hello_heartbeat_interval(payload)
  interval |> should.equal(41_250)
}

pub fn fixture_rate_limit_429_sets_the_window_test() {
  let body = fixtures.must_load("rate_limit_429.json")

  // Headers as a 429 response reports them.
  let headers =
    rest.parse_rate_limit_headers([
      #("x-ratelimit-limit", "5"),
      #("x-ratelimit-remaining", "0"),
      #("x-ratelimit-reset-after", "2.5"),
      #("x-ratelimit-bucket", "fixture-bucket-hash"),
      #("retry-after", "2"),
    ])

  let response =
    RestResponse(
      status: 429,
      headers: [],
      body: body,
      rate_limit_headers: Some(headers),
    )
  let state = rate_limit.update(rate_limit.new(), response)

  // Retry-After (whole seconds) wins the window over reset-after.
  state.retry_after_ms |> should.equal(Some(2000))
  rate_limit.wait_ms(state, 500) |> should.equal(1500)

  // Without a Retry-After header, the reset-after header rules the
  // window: 2.5s. (The body's fractional retry_after is the executor's
  // own fallback, covered by execute's unit tests.)
  let headers_without_retry =
    rest.parse_rate_limit_headers([
      #("x-ratelimit-limit", "5"),
      #("x-ratelimit-remaining", "0"),
      #("x-ratelimit-reset-after", "2.5"),
      #("x-ratelimit-bucket", "fixture-bucket-hash"),
    ])
  let fallback =
    RestResponse(
      status: 429,
      headers: [],
      body: body,
      rate_limit_headers: Some(headers_without_retry),
    )
  let fallback_state = rate_limit.update(rate_limit.new(), fallback)
  fallback_state.retry_after_ms |> should.equal(Some(2500))

  // The bucket header binds the route for later lookups.
  let routes =
    rate_limit.associate(dict.new(), "GET /channels/:id/messages", response)
  let assert Ok(bucket) = dict.get(routes, "GET /channels/:id/messages")
  error.bucket_id_to_string(bucket) |> should.equal("fixture-bucket-hash")
}

pub fn fixture_rate_limit_429_global_body_documented_test() {
  // The global 429 body: same shape, is_global true, whole-second
  // retry_after. Documented here; global handling lives in the
  // executor, which unit tests cover with canned responses.
  let body = fixtures.must_load("rate_limit_429_global.json")
  let assert Ok(_) = json.parse(body, body_shape_decoder())
}

pub type BodyShape {
  BodyShape(code: Int, is_global: Bool, retry_after: option.Option(Float))
}

fn body_shape_decoder() -> d.Decoder(BodyShape) {
  use code <- d.field("code", d.int)
  use is_global <- d.field("global", d.bool)
  use retry_after <- d.optional_field(
    "retry_after",
    None,
    d.optional(d.one_of(d.float, or: [d.map(d.int, int_to_float)])),
  )
  d.success(BodyShape(
    code: code,
    is_global: is_global,
    retry_after: retry_after,
  ))
}

fn int_to_float(value: Int) -> Float {
  int.to_float(value)
}
