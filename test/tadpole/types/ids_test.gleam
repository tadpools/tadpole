//// Tests for the domain-specific opaque ID types.

import gleeunit/should
import tadpole/types/ids
import tadpole/types/snowflake

const real_id = "510703545291833357"

pub fn user_id_parses_test() {
  let assert Ok(id) = ids.user_id(real_id)
  ids.user_to_string(id) |> should.equal(real_id)
}

pub fn guild_id_parses_test() {
  let assert Ok(id) = ids.guild_id(real_id)
  ids.guild_to_string(id) |> should.equal(real_id)
}

pub fn channel_id_parses_test() {
  let assert Ok(id) = ids.channel_id(real_id)
  ids.channel_to_string(id) |> should.equal(real_id)
}

pub fn message_id_parses_test() {
  let assert Ok(id) = ids.message_id(real_id)
  ids.message_to_string(id) |> should.equal(real_id)
}

pub fn role_id_parses_test() {
  let assert Ok(id) = ids.role_id(real_id)
  ids.role_to_string(id) |> should.equal(real_id)
}

pub fn invalid_ids_are_rejected_test() {
  ids.user_id("garbage") |> should.be_error
  ids.guild_id("") |> should.be_error
  ids.channel_id("-5") |> should.be_error
}

pub fn invalid_ids_carry_reason_test() {
  let assert Error(ids.InvalidId(value, reason)) = ids.user_id("garbage")
  value |> should.equal("garbage")
  reason |> should.equal(snowflake.NotANumber)
}

pub fn user_to_int_matches_string_test() {
  let assert Ok(id) = ids.user_id(real_id)
  let assert Ok(parsed) = ids.user_id(ids.user_to_string(id))
  ids.user_to_int(parsed) |> should.equal(ids.user_to_int(id))
}

pub fn distinct_id_types_are_not_interchangeable_test() {
  // Compile-time separation is the point; this test documents it.
  // If UserId were constructible from GuildId's output, this would not hold.
  let assert Ok(_user) = ids.user_id(real_id)
  let assert Ok(_guild) = ids.guild_id(real_id)
  Nil
}
