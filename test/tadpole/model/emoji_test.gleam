//// Tests for the reaction emoji type. The encoding is the load-bearing
//// part: Discord answers `10014: Unknown Emoji` for a path segment that
//// is not URL encoded, and that error names the emoji rather than the
//// encoding, so a wrong one reads like the wrong emoji. These pin the
//// exact bytes that go on the wire.

import gleam/string
import gleeunit/should
import tadpole/model/emoji
import tadpole/types/ids
import tadpole/types/snowflake

fn emoji_id(value: String) -> ids.EmojiId {
  let assert Ok(id) = ids.emoji_id(value)
  id
}

fn custom() -> emoji.Emoji {
  emoji.Custom(name: "lilypad", id: emoji_id("740000000000000001"))
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
