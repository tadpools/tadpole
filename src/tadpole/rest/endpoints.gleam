//// The first REST endpoint bindings: things every bot does in its
//// first hour. Read itself, post a message, reply. Each function
//// builds the request, runs it through tadpole/rest/execute, and
//// decodes the typed model. Transport injection is inherited from
//// execute; the plain functions use the real httpc transport, the
//// `_with` variants accept any transport (tests, proxies, a future JS
//// target).
////
//// Every call runs in a fresh execute session, so rate-limit state
//// learned here does not carry between calls. Single-call bots are
//// fine. Sustained-fire callers should use `execute.send_in_session`
//// directly.
////
//// ## When you reach for this
////
//// - `get_current_user`: smoke-test a token before starting a bot, or
////   fetch the bot's own identity.
//// - `send_message` / `reply`: every text post. `reply` adds a
////   message_reference, so Discord's client shows the original above
////   the reply and pings its author. The returned message's
////   `message_type` is 19 (REPLY).
//// - `get_messages`: read a channel's history. `MessageQuery` picks
////   the anchor and the limit; `MessagePage` carries the cursor for the
////   next page back.
//// - `get_channel` / `get_message`: fetch one object by id.
////
//// Any other route: drop to [`tadpole/rest/execute`](execute.html)
//// with `rest.get`/`rest.post` and decode the payload yourself.
////
//// ## Routes
////
//// | Function | Discord route | Returns |
//// | --- | --- | --- |
//// | `get_current_user` | GET /users/@me | `User` |
//// | `get_channel` | GET /channels/{channel_id} | `Channel` |
//// | `get_message` | GET /channels/{channel_id}/messages/{message_id} | `Message` |
//// | `get_messages` | GET /channels/{channel_id}/messages | `MessagePage` |
//// | `send_message` | POST /channels/{channel_id}/messages | `Message` |
//// | `reply` | POST /channels/{channel_id}/messages, body carries message_reference | `Message` |
//// | `edit_message` | PATCH /channels/{channel_id}/messages/{message_id} | `Message` |
//// | `delete_message` | DELETE /channels/{channel_id}/messages/{message_id} | `Nil` (204) |
////
//// The `_with` variants take the same routes over an injected
//// transport. See each function's doc.
////
//// ## Failure modes
////
//// Errors arrive already mapped by execute:
////
//// - 401: the token is wrong or was reset in the portal.
//// - 403: the bot lacks permission there (for messages: usually Send
////   Messages), or cannot view the channel.
//// - 404: the id is wrong, or the resource is gone (for `reply`, the
////   replied-to message was already deleted).
//// - 429: rate limited. Retried while the client allows, then
////   `error.RateLimited` with the wait.
//// - status 0: no HTTP response happened at all. Network down,
////   timeout. The status-0 convention, tadpole/rest/execute's module
////   doc explains why.
//// - `DecodeFailed`: Discord's payload stopped matching the model.
////
//// Discord truncates content past 2000 characters, silently. The
//// message posts, the tail is gone, no error returns. Check
//// `string.length` yourself if the length matters.
////
//// Two Discord behaviours look like success and are worth stating here,
//// because both are silent. A channel read without Read Message
//// History answers 200 with an empty array rather than 403. A `limit`
//// outside 1-100 is a 400 from Discord, so this module clamps instead
//// of forwarding it.
////
//// ## Concurrency
////
//// Each call is independent and blocks its process for the round trip
//// plus any sleeps. The fresh-session caveat above is the one that
//// bites: a tight loop leans on 429 retries rather than learned
//// waits. Sustained fire on one route belongs in
//// `execute.send_in_session`.
////
//// ## See also
////
//// - [`tadpole/bot`](../bot.html) wraps send_message/reply with a ready client
//// - [`tadpole/rest/execute`](execute.html) the layer below, and the session API
//// - [`tadpole/model/message`](../model/message.html) what comes back

import gleam/dynamic/decode as d
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None}
import gleam/result
import tadpole/error.{type TadpoleError}
import tadpole/model/channel.{type Channel}
import tadpole/model/decode
import tadpole/model/message.{type Message}
import tadpole/model/user.{type User}
import tadpole/rest
import tadpole/rest/execute.{type Transport}
import tadpole/types/ids.{type ChannelId, type MessageId}

/// Which slice of a channel's history to read.
///
/// Discord's `before`, `after` and `around` are mutually exclusive, so
/// this is one variant rather than three independent options. Two
/// anchors cannot be built here, so they cannot be sent, and Discord
/// never has to answer with a 400 for a mistake the type system already
/// refused to represent.
pub type MessageQuery {
  /// The newest messages in the channel, no anchor. This is Discord's
  /// own default and the common case: "what was just said here".
  Latest(limit: Int)
  /// Messages older than `before`, which is how you walk backwards
  /// through history.
  Before(before: MessageId, limit: Int)
  /// Messages newer than `after`.
  After(after: MessageId, limit: Int)
  /// Messages on both sides of `around`.
  Around(around: MessageId, limit: Int)
}

/// One page of history.
///
/// `oldest` is a fact about this page, not a promise about the channel:
/// it is the id of the oldest message Discord returned, which is what
/// the next `MessageQuery.Before` needs. Discord decides where a page
/// ends, so a page shorter than its limit is not by itself the end of
/// history. Keep going while pages come back non-empty.
pub type MessagePage {
  MessagePage(
    /// Exactly as Discord returns them: **newest first**. Discord does
    /// not document an oldest-first option, so a `MessagePage` read as
    /// a list shows the most recent message first.
    messages: List(Message),
    /// The id of the oldest message in `messages`, None when the page
    /// came back empty.
    oldest: Option(MessageId),
  )
}

/// Discord's documented bounds on `limit`. Anything outside is clamped
/// rather than refused, the same way `first_heartbeat_delay_ms` clamps
/// its jitter. Sending an out-of-range limit is a 400 from Discord, and
/// a bot that clamped its own read is a bot that still works.
const min_history_limit = 1

const max_history_limit = 100

/// Discord's documented default, used when a caller wants "whatever is
/// usual" rather than a number.
pub const default_history_limit = 50

/// GET /channels/{channel_id}/messages, one page of a channel's history.
///
/// Fails with RestStatus on non-2xx. 403 means the bot cannot view the
/// channel. 404 means the channel id is wrong.
///
/// One case does not fail and is worth knowing: a bot without Read
/// Message History gets a 200 and an **empty array**, not a 403. An
/// empty page therefore means "nothing visible to you here", which
/// covers both the end of the channel and a missing permission.
pub fn get_messages(
  client: rest.RestClient,
  channel_id: ChannelId,
  query: MessageQuery,
) -> Result(MessagePage, TadpoleError) {
  get_messages_with(
    client,
    execute.httpc_transport(client.timeout_ms),
    channel_id,
    query,
  )
}

/// `get_messages` over an injected transport.
pub fn get_messages_with(
  client: rest.RestClient,
  transport: Transport,
  channel_id: ChannelId,
  query: MessageQuery,
) -> Result(MessagePage, TadpoleError) {
  let request =
    rest.get("/channels/" <> ids.channel_to_string(channel_id) <> "/messages")
    |> with_history_query(query)
  case execute.send(client, request, transport) {
    Ok(response) ->
      decode.from_json(None, response.body, d.list(message.decoder()))
      |> result.map(page)
    Error(e) -> Error(e)
  }
}

/// The query parameters for one variant, in the order they are encoded:
/// the anchor first, then the limit. RestRequest is a public record, so
/// this sets the field directly instead of folding `with_query` over a
/// list and reasoning about prepend order.
fn with_history_query(
  request: rest.RestRequest,
  query: MessageQuery,
) -> rest.RestRequest {
  rest.RestRequest(..request, query: history_params(query))
}

fn history_params(query: MessageQuery) -> List(#(String, String)) {
  case query {
    Latest(limit) -> [limit_param(limit)]
    Before(before, limit) -> [
      anchor_param("before", before),
      limit_param(limit),
    ]
    After(after, limit) -> [anchor_param("after", after), limit_param(limit)]
    Around(around, limit) -> [
      anchor_param("around", around),
      limit_param(limit),
    ]
  }
}

fn anchor_param(name: String, id: MessageId) -> #(String, String) {
  #(name, ids.message_to_string(id))
}

fn limit_param(limit: Int) -> #(String, String) {
  #("limit", int.to_string(clamp_limit(limit)))
}

fn clamp_limit(limit: Int) -> Int {
  int.min(max_history_limit, int.max(min_history_limit, limit))
}

/// Newest first, so the cursor is the last element.
fn page(messages: List(Message)) -> MessagePage {
  let oldest =
    messages
    |> list.last
    |> option.from_result
    |> option.map(fn(message) { message.id })
  MessagePage(messages: messages, oldest: oldest)
}

/// GET /users/@me, the bot's own user object.
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

/// GET /channels/{channel_id}, fetch a channel by its id.
///
/// Fails with RestStatus on non-2xx. 403 means the bot cannot view
/// the channel. 404 means the channel id is wrong or the channel was
/// deleted.
pub fn get_channel(
  client: rest.RestClient,
  channel_id: ChannelId,
) -> Result(Channel, TadpoleError) {
  get_channel_with(
    client,
    execute.httpc_transport(client.timeout_ms),
    channel_id,
  )
}

/// `get_channel` over an injected transport.
pub fn get_channel_with(
  client: rest.RestClient,
  transport: Transport,
  channel_id: ChannelId,
) -> Result(Channel, TadpoleError) {
  case
    execute.send(
      client,
      rest.get("/channels/" <> ids.channel_to_string(channel_id)),
      transport,
    )
  {
    Ok(response) -> channel.from_json(response.body)
    Error(e) -> Error(e)
  }
}

/// GET /channels/{channel_id}/messages/{message_id}, fetch a single
/// message by its id.
///
/// Fails with RestStatus on non-2xx. 403 means the bot lacks Read
/// Message History. 404 means the message or channel id is wrong, or
/// the message was deleted.
pub fn get_message(
  client: rest.RestClient,
  channel_id: ChannelId,
  message_id: MessageId,
) -> Result(Message, TadpoleError) {
  get_message_with(
    client,
    execute.httpc_transport(client.timeout_ms),
    channel_id,
    message_id,
  )
}

/// `get_message` over an injected transport.
pub fn get_message_with(
  client: rest.RestClient,
  transport: Transport,
  channel_id: ChannelId,
  message_id: MessageId,
) -> Result(Message, TadpoleError) {
  case
    execute.send(
      client,
      rest.get(
        "/channels/"
        <> ids.channel_to_string(channel_id)
        <> "/messages/"
        <> ids.message_to_string(message_id),
      ),
      transport,
    )
  {
    Ok(response) -> message.from_json(response.body)
    Error(e) -> Error(e)
  }
}

/// POST /channels/{channel_id}/messages, post `content` to a channel.
///
/// Discord silently truncates content past 2000 characters: the message
/// still goes through, the tail is gone, no error is returned. Tadpole
/// does not second-guess that. Check `string.length` yourself if it
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

/// POST /channels/{channel_id}/messages with a message_reference.
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

/// PATCH /channels/{channel_id}/messages/{message_id} to edit a message
/// the bot owns. Only the bot's own messages can be edited.
///
/// Fails with RestStatus on non-2xx. 403 means the bot does not own
/// the message (only the author can edit). 404 means the message or
/// channel id is wrong, or the message was deleted.
pub fn edit_message(
  client: rest.RestClient,
  channel_id: ChannelId,
  message_id: MessageId,
  new_content: String,
) -> Result(Message, TadpoleError) {
  edit_message_with(
    client,
    execute.httpc_transport(client.timeout_ms),
    channel_id,
    message_id,
    new_content,
  )
}

/// `edit_message` over an injected transport.
pub fn edit_message_with(
  client: rest.RestClient,
  transport: Transport,
  channel_id: ChannelId,
  message_id: MessageId,
  new_content: String,
) -> Result(Message, TadpoleError) {
  let body =
    json.object([#("content", json.string(new_content))]) |> json.to_string
  let request =
    rest.patch(
      "/channels/"
        <> ids.channel_to_string(channel_id)
        <> "/messages/"
        <> ids.message_to_string(message_id),
      body,
    )
  case execute.send(client, request, transport) {
    Ok(response) -> message.from_json(response.body)
    Error(e) -> Error(e)
  }
}

/// DELETE /channels/{channel_id}/messages/{message_id}. Deletes a
/// message. The bot can delete its own messages, or any message in a
/// channel where it has Manage Messages.
///
/// Returns Nil on success (204 No Content). Fails with RestStatus on
/// non-2xx. 403 means the bot lacks permission. 404 means the message
/// or channel id is wrong, or the message was already deleted.
pub fn delete_message(
  client: rest.RestClient,
  channel_id: ChannelId,
  message_id: MessageId,
) -> Result(Nil, TadpoleError) {
  delete_message_with(
    client,
    execute.httpc_transport(client.timeout_ms),
    channel_id,
    message_id,
  )
}

/// `delete_message` over an injected transport.
pub fn delete_message_with(
  client: rest.RestClient,
  transport: Transport,
  channel_id: ChannelId,
  message_id: MessageId,
) -> Result(Nil, TadpoleError) {
  let request =
    rest.delete(
      "/channels/"
      <> ids.channel_to_string(channel_id)
      <> "/messages/"
      <> ids.message_to_string(message_id),
    )
  case execute.send(client, request, transport) {
    Ok(_) -> Ok(Nil)
    Error(e) -> Error(e)
  }
}

/// The message body every text post shares; reply adds message_reference
/// on top of it.
fn encode_content(content: String) -> String {
  json.object([#("content", json.string(content))]) |> json.to_string
}
