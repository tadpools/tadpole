//// The websocket transport: stratus behind a wall. Gateway code sees
//// frames in and a send/close handle out; stratus's Connection and
//// InternalMessage types never cross this module, and neither does the
//// socket. The shard actor owns the protocol state on top of it.
//// Stability: Growing.
////
//// ## When you reach for this
////
//// Almost never directly. [`tadpole/gateway/shard`](shard.html) opens
//// connections and reads frames; [`tadpole/bot`](../bot.html) builds
//// shards. The module exists so the rest of the library can be written
//// and tested without stratus's types in scope, and so a different
//// websocket backend could replace stratus behind the same four
//// functions.
////
//// ## The Connection contract
////
//// `Connection` is opaque: it holds the stratus subject and the owning
//// process id, and nothing outside this module may touch either. That
//// is what makes the socket race-free — only the transport actor ever
//// writes to it.
////
//// - `connect` blocks until the handshake finishes (stratus's 5s connect
////   timeout) and fails with `GatewayConnectFailed` for a bad URL or a
////   failed handshake. Server frames are parsed with
////   [`tadpole/gateway/frame`](frame.html) and forwarded to `inbound`;
////   text that is not a gateway envelope is dropped with a warning,
////   never a crash, and binary frames are ignored (the v10 JSON gateway
////   sends none).
//// - `send_text` blocks until the transport actor has written the frame
////   (up to 5s). If the transport process is already dead, the call
////   crashes the caller — the shard only sends between protocol steps
////   and treats a dead transport as a close, not as data loss to hide.
//// - `close` sends a close frame whose code depends on the intent:
////   `KeepSession` sends 4900 (outside the 1000/1001 pair Discord
////   treats as session invalidation), `EndSession` sends 1000. It
////   returns immediately; the `Closed` notice or process death follows
////   on its own.
////
//// ## TransportDown and Closed
////
//// `Closed(close_code)` arrives on the subject given to `connect` when
//// the server closes the connection: Discord's code when a close frame
//// came, 1006 when the socket died without one. Stratus's close reasons
//// are mapped back to wire codes here — custom 4xxx codes pass through,
//// NotProvided becomes 1006.
////
//// ## Monitor, not link
////
//// A connection can also die with no close at all (process death, a
//// dropped socket) — that is not a `Closed` notice, it is the monitor
//// firing. `connect` starts the connection as its own actor, which
//// links to its spawner like any Gleam actor. The shard immediately
//// severs that link (`process.unlink(transport.owner_pid(conn))`) and
//// monitors the process instead: a transport death must notify the
//// shard, not kill it. The monitor is the death signal; `Closed` is
//// the polite one, and the shard swallows late duplicates with its
//// `closed_handled` flag.
////
//// ## Failure modes
////
//// `connect` fails on a bad URL or a failed handshake; `gateway_request`
//// rejects any scheme that is not `wss`/`ws`. `send_text` and `close`
//// behave as the Connection contract above describes.
////
//// ## See also
////
//// - [`tadpole/gateway/shard`](shard.html) — the only consumer
//// - [`tadpole/gateway/frame`](frame.html) — the frames it forwards

import gleam/erlang/process.{type Pid, type Subject}
import gleam/http
import gleam/http/request.{type Request}
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import gleam/uri
import logging
import stratus
import tadpole/error.{type TadpoleError, BadRequest, GatewayConnectFailed}
import tadpole/gateway/frame.{type Frame}
import tadpole/user_agent

/// A live websocket connection to the gateway. Opaque on purpose: the
/// stratus connection behind it may only be touched from the transport
/// actor, so nothing outside this module can race the socket.
pub opaque type Connection {
  Connection(subject: Subject(stratus.InternalMessage(TransportMsg)), pid: Pid)
}

/// Messages the transport actor runs on. Internal plumbing; public only
/// because the stratus subject's type mentions it. Send `SendClose`
/// (via `close`) to end the connection politely.
pub type TransportMsg {
  SendText(reply: Subject(Result(Nil, TadpoleError)), payload: String)
  SendClose(intent: CloseIntent)
}

/// What a deliberate close means for the session Discord still holds.
/// The docs are explicit: closing with close code 1000 or 1001
/// invalidates the session, and any other close code (or dropping the
/// TCP connection) leaves it valid until it times out. So the intent
/// picks the wire code, and the resume paths get a code outside the
/// invalidating pair.
pub type CloseIntent {
  /// The session must stay valid server-side: the next connection will
  /// RESUME it. Sent as 4900, the convention for "reconnect intended".
  KeepSession
  /// The session is dead or should die: the bot is stopping, or the
  /// next connection will identify fresh. Sent as 1000, the docs' clean
  /// invalidation.
  EndSession
}

const keep_session_close_code = 4900

/// The wire close code an intent sends. Pure so tests can pin exactly
/// what goes on the wire: a keep-session close must never be 1000 or
/// 1001, the pair Discord treats as session invalidation.
@internal
pub fn close_code(intent: CloseIntent) -> Int {
  case intent {
    KeepSession -> keep_session_close_code
    EndSession -> 1000
  }
}

/// Notice that the websocket closed. `close_code` is Discord's close
/// code when the server sent a close frame; 1006 when the socket died
/// without one.
pub type Closed {
  Closed(close_code: Int)
}

type TransportState {
  TransportState(inbound: Subject(Frame), on_closed: Subject(Closed))
}

/// Open a websocket to `url` and run it as its own actor. Parsed gateway
/// frames arrive on `inbound`; when the server closes the connection a
/// `Closed` notice arrives on `on_closed`. Monitor `owner_pid` as well —
/// a connection that dies without a close frame sends no `Closed`.
///
/// Blocks until the websocket handshake finishes (stratus's 5s connect
/// timeout) or fails. Fails with GatewayConnectFailed for a bad URL or a
/// failed handshake.
pub fn connect(
  url: String,
  inbound inbound: Subject(Frame),
  on_closed on_closed: Subject(Closed),
) -> Result(Connection, TadpoleError) {
  use req <- result.try(gateway_request(url))
  let state = TransportState(inbound: inbound, on_closed: on_closed)
  let builder =
    stratus.new(req, state)
    |> stratus.on_message(handle_transport_message)
    |> stratus.on_close(fn(state, reason) {
      process.send(state.on_closed, Closed(reason_code(reason)))
    })

  case stratus.start(builder) {
    Ok(started) -> Ok(Connection(subject: started.data, pid: started.pid))
    Error(start_error) ->
      Error(GatewayConnectFailed(
        reason: error.Other(string.inspect(start_error)),
        attempt: 0,
        next_retry_ms: 0,
      ))
  }
}

/// Send one text frame. Blocks until the transport actor has written it
/// (up to 5s). Fails when the socket refuses the write; if the transport
/// process is gone the call crashes the caller — the shard only sends
/// between protocol steps and treats a dead transport as a close.
pub fn send_text(
  conn: Connection,
  payload: String,
) -> Result(Nil, TadpoleError) {
  process.call(conn.subject, 5000, fn(reply) {
    stratus.to_user_message(SendText(reply, payload))
  })
}

/// Ask the transport to send a close frame and end. The `intent` picks
/// the wire code: `KeepSession` sends 4900 so Discord keeps the session
/// for the resume that follows, `EndSession` sends 1000 to invalidate
/// cleanly. Fire-and-forget: the usual `Closed` notice or process death
/// follows on its own.
pub fn close(conn: Connection, intent: CloseIntent) -> Nil {
  process.send(conn.subject, stratus.to_user_message(SendClose(intent)))
}

/// The process running the connection. The shard monitors it to learn
/// when the connection died and unlinks it so that death cannot take
/// the shard down with it.
@internal
pub fn owner_pid(conn: Connection) -> Pid {
  conn.pid
}

/// The stratus upgrade request for `url`. `wss` maps to TLS and `ws` to
/// plain TCP; anything else is rejected — the gateway is always a
/// websocket URL, and a config typo should fail immediately, not as a
/// handshake mystery.
pub fn gateway_request(url: String) -> Result(Request(String), TadpoleError) {
  case uri.parse(url) {
    Error(_) -> Error(bad_url(url))
    Ok(parsed) ->
      case parsed.scheme, non_empty(parsed.host) {
        Some("wss"), Some(host) -> Ok(build_request(http.Https, parsed, host))
        Some("ws"), Some(host) -> Ok(build_request(http.Http, parsed, host))
        _, _ -> Error(bad_url(url))
      }
  }
}

// gleam/uri parses "wss://" with an empty host; that is no host at all.
fn non_empty(host: option.Option(String)) -> option.Option(String) {
  case host {
    Some("") -> None
    other -> other
  }
}

fn build_request(
  scheme: http.Scheme,
  parsed: uri.Uri,
  host: String,
) -> Request(String) {
  request.Request(
    method: http.Get,
    headers: [user_agent.header()],
    body: "",
    scheme: scheme,
    host: host,
    port: parsed.port,
    path: parsed.path,
    query: parsed.query,
  )
}

fn bad_url(_url: String) -> TadpoleError {
  GatewayConnectFailed(reason: BadRequest, attempt: 0, next_retry_ms: 0)
}

fn handle_transport_message(
  state: TransportState,
  message: stratus.Message(TransportMsg),
  conn: stratus.Connection,
) -> stratus.Next(TransportState, TransportMsg) {
  case message {
    stratus.Text(payload) ->
      case frame.parse(payload) {
        Ok(frame) -> {
          process.send(state.inbound, frame)
          stratus.continue(state)
        }
        Error(_) -> {
          // The envelope never breaks by design; reaching here means the
          // server sent text that is not a gateway frame. Drop it and let
          // the heartbeat watchdog handle whatever follows.
          logging.log(
            logging.Warning,
            "gateway transport: dropped a text frame that was not a gateway envelope",
          )
          stratus.continue(state)
        }
      }
    // Discord's v10 JSON gateway never sends binary frames.
    stratus.Binary(_) -> stratus.continue(state)
    stratus.User(SendText(reply, payload)) -> {
      let outcome = case stratus.send_text_message(conn, payload) {
        Ok(Nil) -> Ok(Nil)
        Error(reason) ->
          Error(GatewayConnectFailed(
            reason: error.Other(
              "websocket send failed: " <> string.inspect(reason),
            ),
            attempt: 0,
            next_retry_ms: 0,
          ))
      }
      process.send(reply, outcome)
      stratus.continue(state)
    }
    stratus.User(SendClose(intent)) -> {
      // The intent picks the code: 4900 keeps the session for a resume,
      // 1000 invalidates it. 1001 would also invalidate, so it is never
      // sent — the docs are explicit about the pair.
      case intent {
        KeepSession -> {
          let _ =
            stratus.close_custom(
              conn,
              code: keep_session_close_code,
              body: <<>>,
            )
          Nil
        }
        EndSession -> {
          let _ = stratus.close(conn, stratus.Normal(<<>>))
          Nil
        }
      }
      stratus.continue(state)
    }
  }
}

/// Map stratus's close reason back to the wire close code. Custom covers
/// every Discord 4xxx code; NotProvided becomes 1006, the abnormal
/// closure the shard already treats as "network went away".
fn reason_code(reason: stratus.CloseReason) -> Int {
  case reason {
    stratus.NotProvided -> 1006
    stratus.Normal(_) -> 1000
    stratus.GoingAway(_) -> 1001
    stratus.ProtocolError(_) -> 1002
    stratus.UnexpectedDataType(_) -> 1003
    stratus.InconsistentDataType(_) -> 1007
    stratus.PolicyViolation(_) -> 1008
    stratus.MessageTooBig(_) -> 1009
    stratus.MissingExtensions(_) -> 1010
    stratus.UnexpectedCondition(_) -> 1011
    stratus.Custom(custom) -> stratus.get_custom_code(custom)
  }
}
