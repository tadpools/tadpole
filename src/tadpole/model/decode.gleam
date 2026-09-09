//// Shared plumbing for the model JSON decoders: snowflake ID fields and
//// the wrapper that turns gleam/json parse errors into DecodeFailed.
//// Nothing here knows about specific models. Later gateway and REST
//// wiring calls these with the event name it knows; the model-level
//// from_json helpers leave the event empty.
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
/// The reported path is relative to the payload root: fields join with
/// dots, list indices go in brackets (`author.id`, `mentions[0].username`),
/// and a payload that is not JSON at all reports `$`. Only the first
/// problem found is reported — fix it and re-run to see the next one.
pub fn from_json(
  event: Option(String),
  payload: String,
  decoder: d.Decoder(t),
) -> Result(t, TadpoleError) {
  case json.parse(payload, decoder) {
    Ok(value) -> Ok(value)
    Error(json.UnexpectedEndOfInput) -> syntax_error(event, "truncated JSON")
    Error(json.UnexpectedByte(byte)) ->
      syntax_error(event, "invalid byte " <> byte)
    Error(json.UnexpectedSequence(sequence)) ->
      syntax_error(event, "invalid escape sequence " <> sequence)
    Error(json.UnableToDecode([])) ->
      // decode.run only fails with at least one error collected, so this
      // arm is a totality guard, not a reachable case.
      Error(DecodeFailed(
        event: event,
        path: "$",
        expected: "a payload matching the decoder",
        got: "no error details",
      ))
    Error(json.UnableToDecode([first, ..])) -> {
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
