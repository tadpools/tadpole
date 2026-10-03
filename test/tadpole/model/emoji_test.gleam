//// Tests for the reaction emoji type and the emoji shapes Discord sends
//// back. The encoding is the load-bearing part of the request side:
//// Discord answers `10014: Unknown Emoji` for a path segment that is not
//// URL encoded, and that error names the emoji rather than the encoding,
//// so a wrong one reads like the wrong emoji. These pin the exact bytes
//// that go on the wire, and the decode side's two nullable fields.

import gleam/dynamic/decode as d
import gleam/json
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import tadpole/model/emoji
import tadpole/types/ids
import tadpole/types/snowflake

/// Run a decoder over a JSON string, the same path model decoding takes.
fn run(
  decoder: d.Decoder(a),
  payload: String,
) -> Result(a, List(d.DecodeError)) {
  case json.parse(payload, d.dynamic) {
    Ok(dynamic) -> d.run(dynamic, decoder)
    Error(_) -> panic as "emoji_test: the test payload is not valid JSON"
  }
}

fn emoji_id(value: String) -> ids.EmojiId {
  let assert Ok(id) = ids.emoji_id(value)
  id
}

fn custom() -> emoji.Emoji {
  emoji.Custom(name: "lilypad", id: emoji_id("740000000000000001"))
}

fn length_of(list: List(a)) -> Int {
  case list {
    [] -> 0
    [_, ..rest] -> 1 + length_of(rest)
  }
}

// path segments

pub fn unicode_emoji_is_percent_encoded_per_utf8_byte_test() {
  // "\u{1F44D}" is four UTF-8 bytes, so four escapes.
  emoji.to_path_segment(emoji.Unicode("\u{1F44D}"))
  |> should.equal("%F0%9F%91%8D")
}

pub fn multi_codepoint_emoji_encodes_every_codepoint_test() {
  // A heart with a variation selector is two codepoints and six bytes.
  // Encoding only the first would be the kind of bug that works on one
  // emoji and fails on another.
  emoji.to_path_segment(emoji.Unicode("\u{2764}\u{FE0F}"))
  |> should.equal("%E2%9D%A4%EF%B8%8F")
}

pub fn ascii_unicode_emoji_passes_through_unencoded_test() {
  // Not every standard emoji is multi-byte, and a bare ASCII one must
  // not come back mangled.
  emoji.to_path_segment(emoji.Unicode("A")) |> should.equal("A")
}

pub fn custom_emoji_sends_name_then_id_test() {
  // The docs name `name:id` as the form. The colon is encoded, which
  // Discord accepts, and the separator survives as %3A.
  emoji.to_path_segment(custom())
  |> should.equal("lilypad%3A740000000000000001")
}

pub fn custom_emoji_encodes_a_name_that_needs_it_test() {
  let e = emoji.Custom(name: "big pond", id: emoji_id("740000000000000002"))
  emoji.to_path_segment(e) |> should.equal("big%20pond%3A740000000000000002")
}

pub fn to_path_segment_can_never_produce_a_slash_test() {
  // Nothing inside an emoji may introduce a path separator, or the
  // request addresses a different route entirely.
  let e = emoji.Custom(name: "a/b", id: emoji_id("740000000000000003"))
  string.contains(emoji.to_path_segment(e), "/") |> should.be_false
}

pub fn to_path_segment_can_never_produce_a_query_marker_test() {
  let e = emoji.Custom(name: "a?b", id: emoji_id("740000000000000004"))
  string.contains(emoji.to_path_segment(e), "?") |> should.be_false
}

// unencoded text

pub fn unicode_to_text_is_the_characters_test() {
  emoji.to_text(emoji.Unicode("\u{1F525}")) |> should.equal("\u{1F525}")
}

pub fn custom_to_text_is_name_colon_id_test() {
  emoji.to_text(custom()) |> should.equal("lilypad:740000000000000001")
}

pub fn to_text_differs_from_the_path_segment_for_custom_test() {
  // Why there are two: one is what a human reads, the other is what the
  // route wants.
  emoji.to_text(custom()) |> should.not_equal(emoji.to_path_segment(custom()))
}

// the id underneath

pub fn custom_id_rejects_a_non_snowflake_test() {
  ids.emoji_id("not-an-id")
  |> should.equal(Error(ids.InvalidId("not-an-id", snowflake.NotANumber)))
}

pub fn custom_id_rejects_a_future_timestamp_test() {
  // The same validation every other id gets, so a typo'd custom emoji
  // id fails here rather than as a 404 from Discord.
  ids.emoji_id("99999999999999999999")
  |> should.equal(
    Error(ids.InvalidId("99999999999999999999", snowflake.TooFarInFuture)),
  )
}

// the shape Discord sends back

pub fn partial_standard_emoji_has_no_id_test() {
  // Discord sends "id": null for a standard emoji rather than leaving
  // the key out, so this exercises the null path and not the absent one.
  let assert Ok(partial) =
    run(emoji.partial_decoder(), "{\"id\":null,\"name\":\"🔥\"}")

  partial.id |> should.equal(None)
  partial.name |> should.equal(Some("🔥"))
  partial.animated |> should.be_false
}

pub fn partial_custom_emoji_keeps_its_id_and_name_test() {
  let assert Ok(partial) =
    run(
      emoji.partial_decoder(),
      "{\"id\":\"740000000000000001\",\"name\":\"lilypad\",\"animated\":true}",
    )

  let assert Some(id) = partial.id
  ids.emoji_to_string(id) |> should.equal("740000000000000001")
  partial.name |> should.equal(Some("lilypad"))
  partial.animated |> should.be_true
}

pub fn partial_emoji_tolerates_a_null_name_test() {
  // The docs scope a null name to reaction emoji: a custom emoji deleted
  // from its guild still turns up, nameless.
  let assert Ok(partial) =
    run(
      emoji.partial_decoder(),
      "{\"id\":\"740000000000000001\",\"name\":null}",
    )

  partial.id |> should.not_equal(None)
  partial.name |> should.equal(None)
}

pub fn partial_emoji_rejects_a_non_snowflake_id_test() {
  let assert Error(_errors) =
    run(emoji.partial_decoder(), "{\"id\":\"nope\",\"name\":\"x\"}")

  Nil
}

pub fn partial_absent_id_reads_the_same_as_a_null_one_test() {
  // Both are "no id", so both are None, which is what a caller matching
  // on a standard emoji needs to be true.
  let assert Ok(absent) = run(emoji.partial_decoder(), "{\"name\":\"🔥\"}")
  let assert Ok(explicit) =
    run(emoji.partial_decoder(), "{\"id\":null,\"name\":\"🔥\"}")

  absent.id |> should.equal(explicit.id)
}

// turning a read emoji back into a request

pub fn to_request_on_a_standard_emoji_test() {
  let assert Ok(partial) =
    run(emoji.partial_decoder(), "{\"id\":null,\"name\":\"🔥\"}")

  let assert Some(request) = emoji.to_request(partial)
  emoji.to_text(request) |> should.equal("🔥")
}

pub fn to_request_on_a_custom_emoji_test() {
  let assert Ok(partial) =
    run(
      emoji.partial_decoder(),
      "{\"id\":\"740000000000000001\",\"name\":\"lilypad\"}",
    )

  let assert Some(request) = emoji.to_request(partial)
  emoji.to_text(request) |> should.equal("lilypad:740000000000000001")
}

pub fn to_request_on_a_nameless_emoji_is_none_test() {
  // Nothing to send: no name to build a Custom from and no characters
  // for a Unicode. This is the deleted-custom-emoji case and the honest
  // answer is that there is no request to make.
  let assert Ok(partial) =
    run(emoji.partial_decoder(), "{\"id\":\"740000000000000001\"}")

  emoji.to_request(partial) |> should.equal(None)
}

// reactions

pub fn reaction_reads_the_count_split_test() {
  let assert Ok(reaction) =
    run(
      emoji.reaction_decoder(),
      "{\"count\":3,\"count_details\":{\"burst\":1,\"normal\":2},\"me\":true,\"emoji\":{\"id\":null,\"name\":\"🔥\"}}",
    )

  reaction.count |> should.equal(3)
  reaction.burst_count |> should.equal(1)
  reaction.normal_count |> should.equal(2)
  reaction.me |> should.be_true
  reaction.me_burst |> should.be_false
  reaction.burst_colors |> should.equal([])
}

pub fn reaction_without_count_details_keeps_count_as_the_truth_test() {
  // An absent split reads 0 and 0 rather than a guessed proportion, and
  // count still carries the whole number.
  let assert Ok(reaction) =
    run(
      emoji.reaction_decoder(),
      "{\"count\":5,\"emoji\":{\"id\":null,\"name\":\"🔥\"}}",
    )

  reaction.count |> should.equal(5)
  reaction.burst_count |> should.equal(0)
  reaction.normal_count |> should.equal(0)
}

pub fn reaction_with_null_count_details_behaves_like_an_absent_one_test() {
  let assert Ok(reaction) =
    run(
      emoji.reaction_decoder(),
      "{\"count\":5,\"count_details\":null,\"emoji\":{\"id\":null,\"name\":\"🔥\"}}",
    )

  reaction.count |> should.equal(5)
  reaction.burst_count |> should.equal(0)
}

pub fn reaction_keeps_burst_colors_when_present_test() {
  let assert Ok(reaction) =
    run(
      emoji.reaction_decoder(),
      "{\"count\":1,\"me_burst\":true,\"burst_colors\":[\"#5865F2\",\"#EB459E\"],\"emoji\":{\"id\":null,\"name\":\"🔥\"}}",
    )

  reaction.me_burst |> should.be_true
  reaction.burst_colors |> should.equal(["#5865F2", "#EB459E"])
}

pub fn reaction_requires_a_count_test() {
  let assert Error(_errors) =
    run(emoji.reaction_decoder(), "{\"emoji\":{\"id\":null,\"name\":\"🔥\"}}")

  Nil
}

pub fn reaction_requires_an_emoji_test() {
  let assert Error(_errors) = run(emoji.reaction_decoder(), "{\"count\":1}")

  Nil
}

pub fn reaction_list_decoder_reads_several_test() {
  let assert Ok(reactions) =
    run(
      emoji.reaction_list_decoder(),
      "[{\"count\":1,\"emoji\":{\"id\":null,\"name\":\"🔥\"}},{\"count\":2,\"emoji\":{\"id\":null,\"name\":\"🎉\"}}]",
    )

  reactions |> length_of |> should.equal(2)
}
