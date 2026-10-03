//// Shared plumbing for the model JSON decoders: snowflake ID fields and
//// the wrapper that turns gleam/json parse errors into DecodeFailed.
//// Nothing here knows about specific models. Gateway and REST wiring
//// call these with the event name they know; the model-level from_json
//// helpers leave the event empty.
////
//// ## When you reach for this
////
//// Through the model decoders (`user.decoder()`, `message.decoder()`,
//// etc.) they call `snowflake_id` and `from_json` internally. Directly
//// when you write a decoder for a new Discord model and need validated
//// snowflake fields. `from_frame` is the gateway path's, used by
//// `tadpole/gateway/events`.
////
//// ## Two payload shapes, two functions
////
//// `from_json` takes a bare object: a REST response body, or an event
//// object on its own. `from_frame` takes a gateway frame envelope and
//// decodes the event object under `d`.
////
//// They are separate because a shared "does this look like an
//// envelope" guess is wrong somewhere. Both shapes arrive in practice,
//// and no model in this library carries a top-level `d` field, so the
//// guess held. It cannot keep holding: a REST body is whatever Discord
//// sent, and one that carries a `d` key would have that key treated as
//// a wrapper to peel, handing the caller a different object with no
//// error. The gateway path knows it has an envelope, so it says so.
////
//// Internals: `snowflake_id` validates Discord's string ids inside the
//// decoder pipeline (a non-snowflake string fails with the offending
//// text in `got`), and both entry points report the first failure with
//// a JSON path. Fields joined by dots, list indices in brackets. See
//// also [`tadpole/types/ids`](../types/ids.html) for the constructors
//// and [`tadpole/error`](../error.html) for the `DecodeFailed` shape.

import gleam/dynamic/decode as d
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option}
import tadpole/error.{type TadpoleError, DecodeFailed}
import tadpole/types/ids

/// A decoder for one Discord ID field. Discord sends snowflakes as JSON
/// strings, so the raw string is validated with `constructor` (ids.user_id
/// and friends) inside the decoder pipeline. A non-string fails as an
/// ordinary type mismatch; a string that is not a snowflake fails with the
/// offending text in the error's `got`.
///
/// e.g. `use id <- d.field("id", decode.snowflake_id(ids.user_id))`
pub fn snowflake_id(
  constructor: fn(String) -> Result(id, ids.InvalidId),
) -> d.Decoder(id) {
  use raw <- d.then(d.string)
  case constructor(raw) {
    Ok(id) -> d.success(id)
    Error(_) -> {
      // d.failure needs a placeholder of the opaque ID type, and only the
      // ids module can build one. "0" is always a valid snowflake (it
      // embeds timestamp 0), so this assert cannot fire. And the
      // placeholder is never returned; only the error below escapes.
      let assert Ok(placeholder) = constructor("0")
      d.failure(placeholder, "a Discord snowflake string")
      |> d.map_errors(fn(errors) {
        list.map(errors, fn(e) { d.DecodeError(..e, found: raw) })
      })
    }
  }
}

/// Parse `payload` with `decoder` as a bare object: a REST response
/// body, or an event object on its own. `event` is the gateway event
/// name when known, for example Some("MESSAGE_CREATE"); None suits
/// REST responses.
///
/// A top-level `d` field is **data here, not an envelope**. That is the
/// whole reason this function is separate from `from_frame`. A REST body
/// is whatever Discord sent, so if it happens to carry a `d` key then
/// `d` is a field of the object being decoded rather than a wrapper to
/// peel off, and decoding it as a wrapper hands the caller the wrong
/// object with no error to notice.
///
/// The reported path is relative to the object: fields join with dots,
/// list indices go in brackets (`author.id`, `mentions[0].username`),
/// and a payload that is not JSON at all reports `$`. Only the first
/// problem found is reported. Fix it and re-run to see the next one.
pub fn from_json(
  event: Option(String),
  payload: String,
  decoder: d.Decoder(t),
) -> Result(t, TadpoleError) {
  case parse_to_dynamic(event, payload) {
    Ok(dynamic) -> run_decoder(event, dynamic, decoder)
    Error(e) -> Error(e)
  }
}

/// Parse `payload` as a gateway frame envelope, where the event object
/// is the value of `d`.
///
/// This is the only function here that unwraps an envelope, and it is
/// for the gateway path only. A payload with no `d` is decoded as-is,
/// because that is what the typed event tests and any replay tool pass,
/// and because a real frame always carries `d` anyway, so there is
/// nothing for strictness to catch here.
pub fn from_frame(
  event: Option(String),
  payload: String,
  decoder: d.Decoder(t),
) -> Result(t, TadpoleError) {
  case parse_to_dynamic(event, payload) {
    Ok(dynamic) -> run_decoder(event, frame_event_object(dynamic), decoder)
    Error(e) -> Error(e)
  }
}

fn parse_to_dynamic(
  event: Option(String),
  payload: String,
) -> Result(d.Dynamic, TadpoleError) {
  case json.parse(payload, d.dynamic) {
    Ok(dynamic) -> Ok(dynamic)
    Error(json.UnexpectedEndOfInput) -> syntax_error(event, "truncated JSON")
    Error(json.UnexpectedByte(byte)) ->
      syntax_error(event, "invalid byte " <> byte)
    Error(json.UnexpectedSequence(sequence)) ->
      syntax_error(event, "invalid escape sequence " <> sequence)
    // d.dynamic never fails, so a parse of it cannot report UnableToDecode;
    // this arm exists for exhaustiveness only.
    Error(json.UnableToDecode(_)) ->
      Error(DecodeFailed(
        event: event,
        path: "$",
        expected: "a JSON payload",
        got: "the payload did not match the decoder",
      ))
  }
}

fn run_decoder(
  event: Option(String),
  dynamic: d.Dynamic,
  decoder: d.Decoder(t),
) -> Result(t, TadpoleError) {
  case d.run(dynamic, decoder) {
    Ok(value) -> Ok(value)
    Error([]) ->
      // decode.run only fails with at least one error collected, so
      // this arm is a totality guard, not a reachable case.
      Error(DecodeFailed(
        event: event,
        path: "$",
        expected: "a payload matching the decoder",
        got: "no error details",
      ))
    Error([first, ..]) -> {
      let #(expected, got) = describe(first)
      Error(DecodeFailed(
        event: event,
        path: path_text(first.path),
        expected: expected,
        got: got,
      ))
    }
  }
}

/// The event object inside a frame envelope, which is the value of `d`.
/// A payload with no `d` is its own event object, so the shape a replay
/// tool or a hand-written test uses still decodes.
fn frame_event_object(dynamic: d.Dynamic) -> d.Dynamic {
  let envelope_decoder = {
    use inner <- d.field("d", d.dynamic)
    d.success(inner)
  }
  case d.run(dynamic, envelope_decoder) {
    Ok(inner) -> inner
    Error(_) -> dynamic
  }
}

fn syntax_error(event: Option(String), got: String) -> Result(t, TadpoleError) {
  Error(DecodeFailed(
    event: event,
    path: "$",
    expected: "a JSON payload",
    got: got,
  ))
}

// stdlib reports a missing field as expected "Field", found "Nothing",
// and a null as found "Nil"; both read badly in rendered advice.
fn describe(e: d.DecodeError) -> #(String, String) {
  case e {
    d.DecodeError("Field", "Nothing", _) -> #(
      "a value for this field",
      "the field is absent",
    )
    d.DecodeError(expected, "Nil", _) -> #(expected, "null")
    d.DecodeError(expected, found, _) -> #(expected, found)
  }
}

/// Empty means the failure was at the payload root.
fn path_text(segments: List(String)) -> String {
  case segments {
    [] -> "$"
    _ -> join(segments)
  }
}

fn join(segments: List(String)) -> String {
  segments
  |> list.fold("", fn(path, segment) {
    case is_index(segment) {
      True -> path <> "[" <> segment <> "]"
      False ->
        case path {
          "" -> segment
          _ -> path <> "." <> segment
        }
    }
  })
}

// Field names in these models are never numeric, so a numeric segment is
// always a list index.
fn is_index(segment: String) -> Bool {
  case int.parse(segment) {
    Ok(_) -> True
    Error(_) -> False
  }
}
