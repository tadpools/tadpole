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

import gleam/uri
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
