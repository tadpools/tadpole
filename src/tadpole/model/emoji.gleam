//// An emoji as the reaction routes need one. Discord puts the emoji in
//// the path rather than the body, URL encoded, and answers
//// `10014: Unknown Emoji` when that is wrong. This module owns the two
//// forms and the encoding, so no caller ever hand-builds a path segment
//// or wonders whether to escape the colon.
//// Stability: Growing.
////
//// ## When you reach for this
////
//// Through [`tadpole/rest/endpoints`](../rest/endpoints.html)'s
//// `add_reaction`, `remove_own_reaction` and `get_reaction_users`,
//// which all take an `Emoji`. Directly when you hold an emoji as text
//// from a command or config and need to decide whether it is a unicode
//// one or a custom one.
////
//// ## The two forms
////
//// The docs name both. A standard emoji is its own unicode characters.
//// A custom emoji belongs to a guild and travels as `name:id`, so
//// `Custom` takes both halves and validates the id as a snowflake,
//// which is what it is.
////
//// ## Failure modes
////
//// Cannot fail. `to_path_segment` is total over both variants.
//// `emoji_id` fails with `InvalidId` on a non-snowflake id, and a
//// `Custom` emoji that does not exist in its guild is a 404 from
//// Discord, not anything this module can know in advance.
////
//// ## See also
////
//// - [`tadpole/types/ids`](../types/ids.html) the `EmojiId` behind `Custom`
//// - [`tadpole/rest/endpoints`](../rest/endpoints.html) the routes that take one
//// The emoji as it arrives inside a payload, which is a different shape
//// from the one you send. `Emoji` is for requests; `PartialEmoji` is
//// what Discord sends inside a reaction or an event. `Reaction` is one
//// emoji's counts on one message, and `model/message` carries the list on
//// every message it decodes, so reading who reacted costs nothing.

import gleam/dynamic/decode as d
import gleam/option.{type Option, None, Some}
import gleam/uri
import tadpole/model/decode
import tadpole/types/ids.{type EmojiId}

/// An emoji for a reaction. Standard unicode characters or a custom guild
/// emoji, which are two different things on the wire and so are two
/// variants here rather than a String the caller formats.
///
///     import tadpole/model/emoji
///     import tadpole/types/ids
///
///     let assert Ok(party_id) = ids.emoji_id("740000000000000001")
///     let face = emoji.Unicode("\u{1F44D}")
///     let custom = emoji.Custom(name: "lilypad", id: party_id)
///
pub type Emoji {
  /// A standard emoji, given as its own unicode characters, for
  /// example "\u{1F44D}". Sent as the characters themselves, encoded.
  Unicode(String)
  /// A custom emoji from a guild, sent as `name:id` per the docs. The
  /// id is a snowflake, so it is validated at construction.
  Custom(name: String, id: EmojiId)
}

/// The path segment for this emoji, percent-encoded and ready to paste
/// between two slashes.
///
/// Encoding is not optional here. Discord rejects an unencoded emoji with
/// `10014: Unknown Emoji`, and the failure names the emoji rather than
/// the encoding, so it reads like the wrong emoji when it is really a
/// malformed path. `uri.percent_encode` handles the whole job in one
/// pass: a multi-byte character is encoded per UTF-8 byte, and the colon
/// in a custom emoji's `name:id` becomes `%3A`, which Discord accepts.
///
///     emoji.to_path_segment(emoji.Unicode("\u{1F44D}"))
///     // -> "%F0%9F%91%8D"
pub fn to_path_segment(emoji: Emoji) -> String {
  case emoji {
    Unicode(characters) -> uri.percent_encode(characters)
    Custom(name: name, id: id) ->
      uri.percent_encode(name <> ":" <> ids.emoji_to_string(id))
  }
}

/// The unencoded text Discord would show for this emoji: the characters
/// for a standard one, `name:id` for a custom one. Useful for logging
/// and for matching an emoji the bot was asked for.
pub fn to_text(emoji: Emoji) -> String {
  case emoji {
    Unicode(characters) -> characters
    Custom(name: name, id: id) -> name <> ":" <> ids.emoji_to_string(id)
  }
}

pub type PartialEmoji {
  PartialEmoji(
    /// None for a standard emoji. Discord sends `"id": null` for those
    /// rather than leaving the key out, so absent and null both land
    /// here as None.
    id: Option(EmojiId),
    /// None when Discord sends null. The docs scope that to reaction
    /// emoji specifically: a custom emoji deleted from its guild still
    /// turns up in a reaction with no name.
    name: Option(String),
    /// Sent only in reaction events, and only for animated emoji, so
    /// False covers every other payload.
    animated: Bool,
  )
}

/// Decoder for the emoji object as it appears inside a reaction.
pub fn partial_decoder() -> d.Decoder(PartialEmoji) {
  use id <- d.optional_field(
    "id",
    None,
    d.optional(decode.snowflake_id(ids.emoji_id)),
  )
  use name <- d.optional_field("name", None, d.optional(d.string))
  use animated <- d.optional_field("animated", False, d.bool)
  d.success(PartialEmoji(id: id, name: name, animated: animated))
}

/// The request form of this emoji, for reacting with the emoji you just
/// read off a message.
///
/// None when there is nothing to send: a nameless emoji has no name and
/// no characters, which is what Discord sends for a custom emoji that
/// has since been deleted from its guild.
pub fn to_request(partial: PartialEmoji) -> Option(Emoji) {
  case partial.id, partial.name {
    Some(id), Some(name) -> Some(Custom(name: name, id: id))
    _, Some(name) -> Some(Unicode(name))
    _, _ -> None
  }
}

/// One emoji's reactions to a message, as Discord counts them.
///
/// Discord splits `count` into normal and super ("burst") reacts in a
/// nested object. The split is flattened here because reading it is the
/// point, and `count` is kept because it is the number that includes both
/// and stays the authority when the split is absent.
pub type Reaction {
  Reaction(
    /// Total reacts, super reacts included. Discord's `count`.
    count: Int,
    /// How many of `count` were super reacts. `count_details.burst`.
    burst_count: Int,
    /// How many of `count` were normal. `count_details.normal`.
    normal_count: Int,
    /// Whether the bot itself reacted with this emoji.
    me: Bool,
    /// Whether the bot super-reacted with this emoji.
    me_burst: Bool,
    emoji: PartialEmoji,
    /// The HEX colours Discord used for super reacts. Populated only by
    /// the payloads that carry super reacts, so empty otherwise.
    burst_colors: List(String),
  )
}

/// Decoder for one entry of a message's `reactions`.
///
/// `count` is required because it is the field every caller wants and
/// there is no honest default for it. `count_details` is optional: when
/// it is absent the split reads 0 and 0, and `count` carries the whole
/// truth. That is the docs' shape today, so treating a missing split as
/// zero rather than guessing a proportion keeps the numbers honest.
pub fn reaction_decoder() -> d.Decoder(Reaction) {
  let count_details_decoder = {
    use burst <- d.optional_field("burst", 0, d.int)
    use normal <- d.optional_field("normal", 0, d.int)
    d.success(#(burst, normal))
  }
  use count <- d.field("count", d.int)
  use details <- d.optional_field(
    "count_details",
    Some(#(0, 0)),
    d.optional(count_details_decoder),
  )
  let #(burst_count, normal_count) = option.unwrap(details, #(0, 0))
  use me <- d.optional_field("me", False, d.bool)
  use me_burst <- d.optional_field("me_burst", False, d.bool)
  use emoji <- d.field("emoji", partial_decoder())
  use burst_colors <- d.optional_field("burst_colors", [], d.list(d.string))
  d.success(Reaction(
    count: count,
    burst_count: burst_count,
    normal_count: normal_count,
    me: me,
    me_burst: me_burst,
    emoji: emoji,
    burst_colors: burst_colors,
  ))
}

/// Decoder for a message's whole `reactions` array.
pub fn reaction_list_decoder() -> d.Decoder(List(Reaction)) {
  d.list(reaction_decoder())
}
