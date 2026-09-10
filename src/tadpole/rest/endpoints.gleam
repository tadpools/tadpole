//// The first REST endpoint bindings: things every bot does in its first
//// hour — read itself, post a message, reply. Each function builds the
//// request, runs it through tadpole/rest/execute, and decodes the typed
//// model. Transport injection is inherited from execute; the plain
//// functions use the real httpc transport, the `_with` variants accept
//// any transport (tests, proxies, a future JS target).
////
//// Every call runs in a fresh execute session, so rate-limit state
//// learned here does not carry between calls: single-call bots are fine,
//// sustained-fire callers should use `execute.send_in_session` directly.
////
//// ## When you reach for this
////
//// - `get_current_user` — smoke-test a token before starting a bot, or
////   fetch the bot's own identity.
//// - `send_message` / `reply` — every text post. `reply` adds a
////   message_reference, so Discord's client shows the original above
////   the reply and pings its author; the returned message's
////   `message_type` is 19 (REPLY).
////
//// Any other route: drop to [`tadpole/rest/execute`](execute.html) with
//// `rest.post`/`rest.get` and decode the payload yourself.
////
//// ## Routes
////
//// | Function | Discord route | Returns |
//// | --- | --- | --- |
//// | `get_current_user` | GET /users/@me | `User` |
//// | `send_message` | POST /channels/{channel_id}/messages | `Message` |
//// | `reply` | POST /channels/{channel_id}/messages, body carries message_reference | `Message` |
////
//// The `_with` variants take the same routes over an injected
//// transport; see each function's doc.
////
//// ## Failure modes
////
//// Errors arrive already mapped by execute:
////
//// - 401 — the token is wrong or was reset in the portal.
//// - 403 — the bot lacks permission there (for messages: usually Send
////   Messages), or cannot view the channel.
//// - 404 — the id is wrong, or the resource is gone (for `reply`, the
////   replied-to message was already deleted).
//// - 429 — rate limited; retried while the client allows, then
////   `error.RateLimited` with the wait.
//// - status 0 — no HTTP response happened at all: network down,
////   timeout. The status-0 convention, tadpole/rest/execute's module
////   doc explains why.
//// - `DecodeFailed` — Discord's payload stopped matching the model.
////
//// Discord truncates content past 2000 characters, silently: the
//// message posts, the tail is gone, no error returns. Check
//// `string.length` yourself if the length matters.
////
//// ## Concurrency
////
//// Each call is independent and blocks its process for the round trip
//// plus any sleeps. The fresh-session caveat above is the one that
//// bites: a tight loop leans on 429 retries rather than learned waits.
//// Sustained fire on one route belongs in `execute.send_in_session`.
////
//// ## See also
////
//// - [`tadpole/bot`](../bot.html) — wraps send_message/reply with a ready client
//// - [`tadpole/rest/execute`](execute.html) — the layer below, and the session API
//// - [`tadpole/model/message`](../model/message.html) — what comes back

import gleam/json
import tadpole/error.{type TadpoleError}
import tadpole/model/message.{type Message}
import tadpole/model/user.{type User}
import tadpole/rest
import tadpole/rest/execute.{type Transport}
import tadpole/types/ids.{type ChannelId, type MessageId}

/// GET /users/@me — the bot's own user object.
///
/// Fails with RestStatus when Discord answers non-2xx (401 means the
/// token is wrong or was reset), with the status-0 RestStatus convention
/// on transport failure, or with DecodeFailed if Discord's payload stops
/// matching the user model.
pub fn get_current_user(client: rest.RestClient) -> Result(User, TadpoleError) {
  get_current_user_with(client, execute.httpc_transport(client.timeout_ms))
}

/// `get_current_user` over an injected transport.
pub fn get_current_user_with(
  client: rest.RestClient,
  transport: Transport,
) -> Result(User, TadpoleError) {
  case execute.send(client, rest.get("/users/@me"), transport) {
    Ok(response) -> user.from_json(response.body)
    Error(e) -> Error(e)
  }
}

/// POST /channels/{channel_id}/messages — post `content` to a channel.
///
/// Discord silently truncates content past 2000 characters: the message
/// still goes through, the tail is gone, no error is returned. Tadpole
/// does not second-guess that — check `string.length` yourself if it
/// matters.
///
/// Concurrency note: each call carries its own rate-limit session, so
/// hammering this in a loop relies on 429 retries rather than learned
/// waits. See the module doc.
pub fn send_message(
  client: rest.RestClient,
  channel_id: ChannelId,
  content: String,
) -> Result(Message, TadpoleError) {
  send_message_with(
    client,
    execute.httpc_transport(client.timeout_ms),
    channel_id,
    content,
  )
}

/// `send_message` over an injected transport.
pub fn send_message_with(
  client: rest.RestClient,
  transport: Transport,
  channel_id: ChannelId,
  content: String,
) -> Result(Message, TadpoleError) {
  let request =
    rest.post(
      "/channels/" <> ids.channel_to_string(channel_id) <> "/messages",
      encode_content(content),
    )
  case execute.send(client, request, transport) {
    Ok(response) -> message.from_json(response.body)
    Error(e) -> Error(e)
  }
}

/// POST /channels/{channel_id}/messages with a message_reference —
/// Discord's reply. The replied-to message shows the reference in the
/// client; the returned message's `message_type` is 19 (REPLY).
pub fn reply(
  client: rest.RestClient,
  channel_id: ChannelId,
  message_id: MessageId,
  content: String,
) -> Result(Message, TadpoleError) {
  reply_with(
    client,
    execute.httpc_transport(client.timeout_ms),
    channel_id,
    message_id,
    content,
  )
}

/// `reply` over an injected transport.
pub fn reply_with(
  client: rest.RestClient,
  transport: Transport,
  channel_id: ChannelId,
  message_id: MessageId,
  content: String,
) -> Result(Message, TadpoleError) {
  let body =
    json.object([
      #("content", json.string(content)),
      #(
        "message_reference",
        json.object([
          #("message_id", json.string(ids.message_to_string(message_id))),
        ]),
      ),
    ])
    |> json.to_string
  let request =
    rest.post(
      "/channels/" <> ids.channel_to_string(channel_id) <> "/messages",
      body,
    )
  case execute.send(client, request, transport) {
    Ok(response) -> message.from_json(response.body)
    Error(e) -> Error(e)
  }
}

/// The message body every text post shares; reply adds message_reference
/// on top of it.
fn encode_content(content: String) -> String {
  json.object([#("content", json.string(content))]) |> json.to_string
}
