//// One gateway connection, end to end: HELLO, heartbeats, identify or
//// resume, close-code decisions, reconnect with backoff. The shard actor
//// owns all protocol state — sequence, session id, heartbeat misses — so
//// a transport can die without losing the session it will resume with.
//// Decisions that do not need a socket are pure functions here, mirrored
//// against the tables in tadpole/gateway.
//// Stability: Growing.
////
//// Almost every bot meets this module through [`tadpole/bot`](../bot.html),
//// which builds the ShardConfig, runs the dispatch loop, and logs
//// Lifecycle notices. Come here directly to run a shard with your own
//// event sink — a custom dispatcher, a test harness, a second consumer
//// of lifecycle data.
////
//// ## When you reach for this
////
//// `start` gives back a subject; typed events flow to the subject you
//// passed as `events`, and connection news to the `lifecycle` subject if
//// you supplied one. Connection trouble is not a `start` failure:
//// attempts retry with backoff and report through `lifecycle` instead.
////
//// ## ShardConfig, field by field
////
//// - `token` — the bot token, sent inside IDENTIFY and RESUME payloads.
//// - `intents` — the raw bitfield Discord expects in IDENTIFY. Build it
////   with tadpole/intent and `intent.to_int`, not by hand.
//// - `shard` — `#(shard_id, shard_count)`, Discord's documented order.
////   One shard this milestone: `#(0, 1)`.
//// - `url` — the full gateway URL including version and encoding, e.g.
////   `wss://gateway.discord.gg/?v=10&encoding=json` (bot.gleam's
////   constant). No default; the caller always names one.
//// - `lifecycle` — `Some(subject)` to receive Lifecycle notices, `None`
////   to run silent.
////
//// ## Lifecycle
////
//// - `Connected` — the websocket handshake succeeded; HELLO has not
////   arrived, so identify/resume has not run.
//// - `Disconnected(close_code, will_resume)` — the connection closed.
////   `close_code` is Discord's code, or 1006 when the transport died
////   without one. `will_resume` is the decision that follows.
//// - `ConnectFailed(error)` — one connect attempt failed; a retry is
////   already scheduled. Expect this repeatedly during outages.
////
//// ## ShardMsg and the reconnect ladder
////
//// `ShardMsg` is the actor's message type, public only because the
//// subject's type mentions it. Callers send `Stop`; every other variant
//// (HeartbeatTick, Inbound, SocketClosed, TransportDown, ReconnectNow)
//// is plumbing driven by timers and the transport. `Stop` closes the
//// socket and stops the actor; it does not wait for Discord to
//// acknowledge the close frame.
////
//// The close-code ladder, applied by `next_action_on_close` and tested
//// against [`tadpole/gateway`](../gateway.html):
////
//// | Situation | Action |
//// | --- | --- |
//// | close 4003 (not authenticated) / 4004 (auth failed) | `GiveUp` — a config problem; retrying without a fix loops |
//// | close 1000, 1001, 1006, 4000, 4001, 4002, with a stored session | `Resume` |
//// | same codes, no stored session | `IdentifyFresh` |
//// | close 4005-4014, or any other code | `IdentifyFresh` — the session is gone or unusable |
//// | op 9 Invalid Session, `d` = true | `Resume` — outranks whatever close code follows |
//// | op 9 Invalid Session, `d` = false | `IdentifyFresh`; the stored session is forgotten |
//// | transport died with no close frame | treated as 1006 |
//// | 3 missed heartbeat ACKs | close, forget the session, reconnect fresh |
////
//// ## Heartbeat and zombie rules
////
//// HELLO carries the heartbeat interval — floored at 1s, and 45s if
//// Discord's HELLO is unreadable, so zombie detection keeps running.
//// Each tick sends a HEARTBEAT carrying the last sequence number and
//// re-arms itself; there is no separate timer process to supervise.
//// Discord can also demand an immediate heartbeat (op 1, often around
//// RESUME); the shard answers with the current sequence. A HEARTBEAT_ACK
//// resets the miss counter; after `gateway.max_missed_acks` (3) missed
//// ACKs the connection is a zombie and the shard reconnects fresh.
////
//// Reconnects wait `gateway.backoff_ms(attempts)`: 1s, 2s, 4s, ... capped
//// at 60s, no jitter. HELLO resets the attempt counter.
////
//// ## Concurrency
////
//// The shard is one actor and owns all state: session id, sequence,
//// heartbeat counters, the connection, its timers. Nothing to lock.
////
//// - `process.send` to the shard subject, the events subject, or the
////   lifecycle subject is safe from any process; sends are async and
////   never block.
//// - The events subject can only be received by its owner. Create it in
////   the process that will read it.
//// - `start` blocks its caller for at most one websocket handshake
////   (~5s); everything after that is async.
//// - `next_action_on_close` and `on_invalid_session` are pure — safe to
////   call anywhere, which is how tests pin the ladder.
////
//// ## Example
////
//// ```gleam
//// import gleam/erlang/process
//// import gleam/option.{Some}
//// import tadpole/gateway/shard
//// import tadpole/intent
////
//// // Illustrative — tadpole/bot wires exactly this.
//// pub fn run_shard(token: String) -> process.Subject(shard.ShardMsg) {
////   let events = process.new_subject()
////   let lifecycle = process.new_subject()
////   let assert Ok(shard_subject) =
////     shard.start(
////       shard.ShardConfig(
////         token: token,
////         intents: intent.to_int(
////           intent.new() |> intent.enable(intent.guild_messages),
////         ),
////         shard: #(0, 1),
////         url: "wss://gateway.discord.gg/?v=10&encoding=json",
////         lifecycle: Some(lifecycle),
////       ),
////       events: events,
////     )
////   // Read `events` in this process; send shard.Stop to close it.
////   shard_subject
//// }
//// ```
////
//// ## See also
////
//// - [`tadpole/gateway`](../gateway.html) — the pure tables this actor applies
//// - [`tadpole/gateway/transport`](transport.html) — the websocket under the actor
//// - [`tadpole/bot`](../bot.html) — the user-facing wiring of this module

import gleam/dynamic/decode as d
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/json
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/result
import logging
import tadpole/error.{type TadpoleError}
import tadpole/gateway
import tadpole/gateway/events.{type Event}
import tadpole/gateway/frame.{type Frame}
import tadpole/gateway/opcode
import tadpole/gateway/transport

/// A close code to assume when the transport died without one. Abnormal
/// closure: reconnect, keep the session — the network, not Discord's
/// session store, is what failed.
const abnormal_close = 1006

/// Never let a bad HELLO turn into a zero-delay heartbeat storm.
const min_heartbeat_ms = 1000

pub type ShardConfig {
  ShardConfig(
    token: String,
    intents: Int,
    /// #(shard_id, shard_count), Discord's documented order.
    shard: #(Int, Int),
    url: String,
    /// Optional lifecycle notices: connected, disconnected (with close
    /// code and what happens next), connect failures. Discord's close
    /// codes ride along here.
    lifecycle: Option(Subject(Lifecycle)),
  )
}

pub type Lifecycle {
  /// The websocket handshake succeeded; HELLO has not arrived yet.
  Connected
  Disconnected(close_code: Int, will_resume: Bool)
  ConnectFailed(error: TadpoleError)
}

/// Messages the shard actor runs on. Internal plumbing — the subject
/// type leaks it, but callers only ever send `Stop` themselves.
pub type ShardMsg {
  /// Heartbeat interval fired. The shard re-arms the timer after each
  /// tick, so there is no separate timer process to supervise.
  HeartbeatTick
  /// A parsed gateway frame arrived from the transport.
  Inbound(frame: Frame)
  /// The websocket closed; carries Discord's close code when one was
  /// sent (1006 when the transport died without one).
  SocketClosed(close_code: Int)
  /// The transport process died without a close frame. Late notices for
  /// an already-handled close are ignored by the shard.
  TransportDown
  /// Backoff elapsed; retry the connection.
  ReconnectNow
  /// Close the connection and stop the actor. Does not wait for Discord
  /// to acknowledge the close frame.
  Stop
}

/// What the shard does after a websocket close. Tested against the
/// close-code table in tadpole/gateway; the actor applies it verbatim.
pub type CloseAction {
  /// Reconnect and RESUME the stored session.
  Resume
  /// Reconnect and IDENTIFY as a brand new session.
  IdentifyFresh
  /// Do not reconnect: 4003/4004 are config problems, and retrying
  /// without fixing the token just loops.
  GiveUp
}

/// The close-code decision: reconnectable codes reconnect, resumable
/// codes with a stored session resume, everything else starts fresh.
pub fn next_action_on_close(close_code: Int, has_session: Bool) -> CloseAction {
  case gateway.should_reconnect(close_code) {
    False -> GiveUp
    True ->
      case gateway.can_resume(close_code) && has_session {
        True -> Resume
        False -> IdentifyFresh
      }
  }
}

/// Op 9 Invalid Session carries its own verdict, which outranks whatever
/// close code follows: `True` means the session is still there and RESUME
/// is allowed, `False` means it is gone and a fresh identify is due.
pub fn on_invalid_session(resumable: Bool) -> CloseAction {
  case resumable {
    True -> Resume
    False -> IdentifyFresh
  }
}

/// Start one shard: an actor that connects to `config.url`, identifies
/// (or resumes a stored session), heartbeats on Discord's interval, and
/// dispatches typed events to `events`. `start` itself never fails on
/// network problems — connection attempts retry with gateway backoff and
/// report through `config.lifecycle` — so callers get a subject back and
/// the shard does the rest.
///
/// The initialiser blocks for at most one websocket handshake (~5s).
/// Stop the shard by sending it `Stop`.
pub fn start(
  config: ShardConfig,
  events events: Subject(Event),
) -> Result(Subject(ShardMsg), TadpoleError) {
  let result =
    actor.new_with_initialiser(15_000, fn(subject) {
      let inbound = process.new_subject()
      let tick = process.new_subject()
      let closed = process.new_subject()
      let selector =
        process.new_selector()
        |> process.select(subject)
        |> process.select_map(tick, fn(_) { HeartbeatTick })
        |> process.select_map(inbound, Inbound)
        |> process.select_map(closed, fn(c: transport.Closed) {
          SocketClosed(c.close_code)
        })
        |> process.select_monitors(fn(_) { TransportDown })
      let state =
        ShardState(
          config: config,
          events: events,
          self: subject,
          inbound: inbound,
          tick: tick,
          closed: closed,
          session_id: None,
          sequence: None,
          heartbeat: gateway.HeartbeatState(0, 0, 0),
          connection: None,
          monitor: None,
          resume_next: False,
          attempts: 0,
          closed_handled: False,
          heartbeat_timer: None,
          reconnect_timer: None,
        )
      actor.initialised(establish(state))
      |> actor.selecting(selector)
      |> actor.returning(subject)
      |> Ok
    })
    |> actor.on_message(handle)
    |> actor.start

  case result {
    Ok(started) -> Ok(started.data)
    Error(_) ->
      Error(error.InternalContractViolation(
        location: "shard.start",
        details: "shard actor failed to start",
        cause: None,
      ))
  }
}

type ShardState {
  ShardState(
    config: ShardConfig,
    events: Subject(Event),
    self: Subject(ShardMsg),
    inbound: Subject(Frame),
    tick: Subject(Nil),
    closed: Subject(transport.Closed),
    session_id: Option(String),
    sequence: Option(Int),
    heartbeat: gateway.HeartbeatState,
    connection: Option(transport.Connection),
    monitor: Option(process.Monitor),
    /// The next connection should try RESUME before IDENTIFY.
    resume_next: Bool,
    /// Failed connects/reconnects since the last HELLO.
    attempts: Int,
    /// This connection's close has already been handled; swallow late
    /// SocketClosed/TransportDown notices for it.
    closed_handled: Bool,
    heartbeat_timer: Option(process.Timer),
    reconnect_timer: Option(process.Timer),
  )
}

fn handle(
  state: ShardState,
  msg: ShardMsg,
) -> actor.Next(ShardState, ShardMsg) {
  case msg {
    HeartbeatTick -> on_tick(state)
    Inbound(frame) -> on_frame(state, frame)
    SocketClosed(code) -> on_closed(state, code)
    TransportDown ->
      case state.closed_handled {
        True -> actor.continue(state)
        False -> on_closed(state, abnormal_close)
      }
    ReconnectNow -> on_reconnect(state)
    Stop -> shutdown(state)
  }
}

fn on_frame(
  state: ShardState,
  frame: Frame,
) -> actor.Next(ShardState, ShardMsg) {
  let state = case frame.sequence {
    Some(seq) -> ShardState(..state, sequence: Some(seq))
    None -> state
  }
  case frame.opcode {
    opcode.Dispatch -> dispatch(state, frame)
    opcode.Hello -> on_hello(state, frame.raw)
    opcode.HeartbeatAck ->
      actor.continue(
        ShardState(..state, heartbeat: gateway.ack_received(state.heartbeat)),
      )
    opcode.Heartbeat -> {
      // Discord wants a heartbeat right now (often around RESUME).
      let _ = send_payload(state, frame.heartbeat_payload(state.sequence))
      actor.continue(state)
    }
    opcode.Reconnect -> {
      // Discord asked for a reconnect and keeps the session. Close and
      // let the close machinery decide the details — with the session
      // still stored it always lands on Resume.
      cancel_heartbeat(state)
      |> close_socket
      |> actor.continue
    }
    opcode.InvalidSession -> on_invalid_session_frame(state, frame.raw)
    _ -> actor.continue(state)
  }
}

fn dispatch(
  state: ShardState,
  frame: Frame,
) -> actor.Next(ShardState, ShardMsg) {
  case frame.event_name {
    None -> {
      logging.log(
        logging.Warning,
        "shard: dispatch frame arrived without an event name; dropped",
      )
      actor.continue(state)
    }
    Some(name) -> {
      // READY carries the session id RESUME needs later. A targeted
      // decoder reads it straight from the raw frame — a READY whose
      // other fields fail to decode still keeps the session alive.
      let state = case name, session_id_from_ready(frame.raw) {
        "READY", Some(session_id) ->
          ShardState(..state, session_id: Some(session_id))
        _, _ -> state
      }
      let event = case events.decode(name, frame.raw) {
        Ok(event) -> event
        // A known event whose payload moved under us degrades to data,
        // never a crash: forward the raw bytes as Unknown.
        Error(_) -> events.Unknown(name, frame.raw)
      }
      process.send(state.events, event)
      actor.continue(state)
    }
  }
}

fn on_hello(
  state: ShardState,
  raw: String,
) -> actor.Next(ShardState, ShardMsg) {
  let interval = case frame.hello_heartbeat_interval(raw) {
    Ok(interval) -> int.max(interval, min_heartbeat_ms)
    // Discord always sends a sane interval; if it does not, this keeps
    // zombie detection running instead of hanging forever.
    Error(_) -> 45_000
  }
  let state =
    ShardState(
      ..state,
      // A HELLO means the connection is real: reset the backoff counter.
      attempts: 0,
      heartbeat: gateway.HeartbeatState(interval, 0, 0),
      heartbeat_timer: Some(process.send_after(state.tick, interval, Nil)),
    )
  case state.resume_next, state.session_id, state.sequence {
    True, Some(session_id), Some(sequence) -> {
      let _ =
        send_payload(
          state,
          frame.resume_payload(state.config.token, session_id, sequence),
        )
      actor.continue(state)
    }
    _, _, _ -> {
      let _ =
        send_payload(
          state,
          frame.identify_payload(
            state.config.token,
            state.config.intents,
            state.config.shard,
          ),
        )
      actor.continue(
        ShardState(
          ..state,
          session_id: None,
          sequence: None,
          resume_next: False,
        ),
      )
    }
  }
}

fn on_invalid_session_frame(
  state: ShardState,
  raw: String,
) -> actor.Next(ShardState, ShardMsg) {
  let resumable = frame.invalid_session_resumable(raw) |> result.unwrap(False)
  case on_invalid_session(resumable) {
    Resume -> {
      cancel_heartbeat(state)
      |> close_socket
      |> actor.continue
    }
    // Discord threw the session away; forget it so the close machinery
    // lands on IdentifyFresh. Its 1-5s identify wait is satisfied by the
    // reconnect backoff.
    IdentifyFresh -> {
      let state = ShardState(..state, session_id: None, sequence: None)
      cancel_heartbeat(state)
      |> close_socket
      |> actor.continue
    }
    GiveUp -> actor.continue(state)
  }
}

fn on_tick(state: ShardState) -> actor.Next(ShardState, ShardMsg) {
  case state.connection, state.closed_handled {
    Some(conn), False -> {
      let _ = transport.send_text(conn, frame.heartbeat_payload(state.sequence))
      let #(heartbeat, zombie) = gateway.ack_missed(state.heartbeat)
      let state =
        ShardState(
          ..state,
          heartbeat: heartbeat,
          heartbeat_timer: Some(process.send_after(
            state.tick,
            heartbeat.interval_ms,
            Nil,
          )),
        )
      case zombie {
        False -> actor.continue(state)
        True -> {
          logging.log(
            logging.Warning,
            "shard: "
              <> int.to_string(gateway.max_missed_acks)
              <> " heartbeat acks missed; reconnecting fresh",
          )
          actor.continue(close_and_reconnect(state, abnormal_close, False, True))
        }
      }
    }
    _, _ -> actor.continue(state)
  }
}

fn on_closed(state: ShardState, code: Int) -> actor.Next(ShardState, ShardMsg) {
  case state.closed_handled {
    True -> actor.continue(state)
    False ->
      case next_action_on_close(code, option.is_some(state.session_id)) {
        GiveUp -> {
          logging.log(
            logging.Error,
            "shard: gateway closed ("
              <> gateway.close_code_name(code)
              <> "); not reconnecting",
          )
          notify(state.config.lifecycle, Disconnected(code, False))
          shutdown(state)
        }
        Resume -> actor.continue(close_and_reconnect(state, code, True, False))
        IdentifyFresh ->
          actor.continue(close_and_reconnect(state, code, False, True))
      }
  }
}

fn on_reconnect(state: ShardState) -> actor.Next(ShardState, ShardMsg) {
  // Swallow the old monitor's death notice before killing the old
  // transport, or it would arrive as a fresh TransportDown later.
  let state = case state.monitor {
    Some(monitor) -> {
      process.demonitor_process(monitor)
      ShardState(..state, monitor: None)
    }
    None -> state
  }
  let state = case state.connection {
    Some(conn) -> {
      transport.close(conn)
      process.kill(transport.owner_pid(conn))
      ShardState(..state, connection: None)
    }
    None -> state
  }
  actor.continue(establish(ShardState(..state, reconnect_timer: None)))
}

fn shutdown(state: ShardState) -> actor.Next(ShardState, ShardMsg) {
  cancel_heartbeat(state)
  |> cancel_reconnect
  |> close_socket
  |> fn(state) {
    case state.monitor {
      Some(monitor) -> process.demonitor_process(monitor)
      None -> Nil
    }
    case state.connection {
      Some(conn) -> process.kill(transport.owner_pid(conn))
      None -> Nil
    }
  }
  actor.stop()
}

/// Connect (or reconnect). Called from the initialiser and from
/// ReconnectNow; never fails the actor — failures schedule a retry.
fn establish(state: ShardState) -> ShardState {
  case transport.connect(state.config.url, state.inbound, state.closed) {
    Ok(conn) -> {
      let pid = transport.owner_pid(conn)
      // The transport dies with the socket; that death must not take the
      // shard down with it. The monitor is the death signal instead.
      process.unlink(pid)
      let monitor = process.monitor(pid)
      notify(state.config.lifecycle, Connected)
      ShardState(
        ..state,
        connection: Some(conn),
        monitor: Some(monitor),
        closed_handled: False,
      )
    }
    Error(e) -> {
      notify(state.config.lifecycle, ConnectFailed(e))
      schedule_reconnect(state)
    }
  }
}

fn close_and_reconnect(
  state: ShardState,
  code: Int,
  will_resume: Bool,
  forget_session: Bool,
) -> ShardState {
  notify(state.config.lifecycle, Disconnected(code, will_resume))
  let state = cancel_heartbeat(state)
  let state = close_socket(state)
  let state = case forget_session {
    True ->
      ShardState(..state, session_id: None, sequence: None, resume_next: False)
    False -> ShardState(..state, resume_next: will_resume)
  }
  schedule_reconnect(ShardState(..state, closed_handled: True))
}

fn schedule_reconnect(state: ShardState) -> ShardState {
  case state.reconnect_timer {
    Some(_) -> state
    None -> {
      let timer =
        process.send_after(
          state.self,
          gateway.backoff_ms(state.attempts),
          ReconnectNow,
        )
      ShardState(
        ..state,
        reconnect_timer: Some(timer),
        attempts: state.attempts + 1,
      )
    }
  }
}

fn cancel_heartbeat(state: ShardState) -> ShardState {
  case state.heartbeat_timer {
    Some(timer) -> {
      process.cancel_timer(timer)
      ShardState(..state, heartbeat_timer: None)
    }
    None -> state
  }
}

fn cancel_reconnect(state: ShardState) -> ShardState {
  case state.reconnect_timer {
    Some(timer) -> {
      process.cancel_timer(timer)
      ShardState(..state, reconnect_timer: None)
    }
    None -> state
  }
}

fn close_socket(state: ShardState) -> ShardState {
  case state.connection {
    // A dead transport drops the message silently; either way the close
    // machinery has already run or the monitor fires next.
    Some(conn) -> transport.close(conn)
    None -> Nil
  }
  state
}

fn send_payload(
  state: ShardState,
  payload: String,
) -> Result(Nil, TadpoleError) {
  case state.connection {
    Some(conn) -> transport.send_text(conn, payload)
    None -> Ok(Nil)
  }
}

fn notify(lifecycle: Option(Subject(Lifecycle)), event: Lifecycle) -> Nil {
  case lifecycle {
    Some(subject) -> process.send(subject, event)
    None -> Nil
  }
}

/// READY's `d` is the only place a session id is handed out. Read just
/// that field, straight from the raw frame.
fn session_id_from_ready(raw: String) -> Option(String) {
  let session_decoder = {
    use session_id <- d.field("session_id", d.string)
    d.success(session_id)
  }
  let decoder = {
    use session_id <- d.field("d", session_decoder)
    d.success(session_id)
  }
  case json.parse(raw, decoder) {
    Ok(session_id) -> Some(session_id)
    Error(_) -> None
  }
}
