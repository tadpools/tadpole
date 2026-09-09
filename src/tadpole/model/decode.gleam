//// Shared plumbing for the model JSON decoders: snowflake ID fields and
//// the wrapper that turns gleam/json parse errors into DecodeFailed.
//// Nothing here knows about specific models. Gateway and REST wiring
//// call these with the event name they know; the model-level from_json
//// helpers leave the event empty.
////
//// `from_json` takes either a bare event object or a full gateway frame
//// envelope with the event object under `d`, because both shapes arrive
//// in practice: the shard decodes dispatch frames as the envelope, the
//// REST paths decode bare response objects.
////
//// Internals: `snowflake_id` validates Discord's string ids inside the
//// decoder pipeline (a non-snowflake string fails with the offending
//// text in `got`), and `from_json` reports the first failure with a
//// JSON path — fields joined by dots, list indices in brackets. See
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
      // embeds timestamp 0), so this assert cannot fire — and the
      // placeholder is never returned; only the error below escapes.
      let assert Ok(placeholder) = constructor("0")
      d.failure(placeholder, "a Discord snowflake string")
      |> d.map_errors(fn(errors) {
        list.map(errors, fn(e) { d.DecodeError(..e, found: raw) })
      })
    }
  }
}

/// Parse `payload` with `decoder`, folding every failure into
/// error.DecodeFailed. `event` is the gateway event name when known, for
/// example Some("MESSAGE_CREATE"); None suits REST responses.
///
/// The payload may be a bare event object (what the model from_json
/// helpers and the REST paths get) or a full gateway frame envelope with
/// the event object under `d` (what frame.parse hands the shard). When
/// the parsed JSON carries a `d` field, the decoder runs on that inner
/// value; otherwise it runs on the payload as-is.
///
/// The reported path is relative to the event object: fields join with
/// dots, list indices go in brackets (`author.id`, `mentions[0].username`),
/// and a payload that is not JSON at all reports `$`. Only the first
/// problem found is reported — fix it and re-run to see the next one.
pub fn from_json(
  event: Option(String),
  payload: String,
  decoder: d.Decoder(t),
) -> Result(t, TadpoleError) {
  case json.parse(payload, d.dynamic) {
    Ok(dynamic) ->
      case d.run(event_object(dynamic), decoder) {
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

/// The Dynamic the event decoder runs on: the `d` field's value when the
/// payload is a gateway frame envelope, the payload itself when it is a
/// bare event object. No event object in this library carries a `d`
/// field of its own, so the presence of `d` is an envelope, and a null
/// `d` fails the event decoder honestly at the root.
fn event_object(dynamic: d.Dynamic) -> d.Dynamic {
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
