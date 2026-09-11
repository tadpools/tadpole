//// Config builder and validation tests.
//// Also the gleeunit entry point: `gleam test` starts here and discovers
//// every `*_test` function across all test modules.

import gleam/list
import gleam/string
import gleeunit
import gleeunit/should
import tadpole
import tadpole/error
import tadpole/intent

pub fn main() {
  gleeunit.main()
}

pub fn config_new_sets_token_test() {
  let config = tadpole.new("my_secret_token")
  config.token |> should.equal("my_secret_token")
}

pub fn config_new_defaults_test() {
  let config = tadpole.new("token")
  config.shard_count |> should.equal(1)
  config.rest_timeout_ms |> should.equal(30_000)
  config.retry_on_429 |> should.be_true
  config.max_retries |> should.equal(3)
  config.gateway_reconnect |> should.be_true
}

pub fn config_with_intents_test() {
  let config =
    tadpole.new("token")
    |> tadpole.with_intents(
      intent.new()
      |> intent.enable(intent.Guilds)
      |> intent.enable(intent.GuildMessages),
    )

  let enabled = intent.enabled(config.intents)
  list.length(enabled) |> should.equal(2)
  list.contains(enabled, intent.Guilds) |> should.be_true
  list.contains(enabled, intent.GuildMessages) |> should.be_true
}

pub fn config_with_shards_test() {
  let config = tadpole.new("token") |> tadpole.with_shards(4)
  config.shard_count |> should.equal(4)
}

pub fn config_with_rest_timeout_test() {
  let config = tadpole.new("token") |> tadpole.with_rest_timeout(5000)
  config.rest_timeout_ms |> should.equal(5000)
}

pub fn config_builder_chain_is_immutable_test() {
  // Builders must not mutate: the original config is untouched.
  let original = tadpole.new("token")
  let _modified =
    original |> tadpole.with_shards(8) |> tadpole.with_rest_timeout(1000)

  original.shard_count |> should.equal(1)
  original.rest_timeout_ms |> should.equal(30_000)
}

pub fn validate_rejects_empty_token_test() {
  let assert Error(error.MissingToken) = tadpole.validate(tadpole.new(""))
  Nil
}

pub fn validate_rejects_whitespace_token_test() {
  let assert Error(error.MissingToken) = tadpole.validate(tadpole.new("   "))
  Nil
}

pub fn validate_rejects_token_with_quotes_test() {
  // The classic copy-paste mistake: quotes included.
  let assert Error(error.InvalidTokenFormat(_)) =
    tadpole.validate(tadpole.new(
      "\"MTIzNDU2Nzg5MDEyMzQ1Njc4OTAxMjM0NTY3ODkwMTIzNDU2Nzg5\"",
    ))
  Nil
}

pub fn validate_rejects_token_with_spaces_test() {
  let assert Error(error.InvalidTokenFormat(_)) =
    tadpole.validate(tadpole.new(
      "MTIzNDU2Nzg5 MDEyMzQ1Njc4OTAxMjM0NTY3ODkwMTIzNDU2Nzg5",
    ))
  Nil
}

pub fn validate_accepts_well_formed_token_test() {
  // A structurally plausible token: three parts, no whitespace, and
  // obviously synthetic so secret scanners never mistake it for real.
  let assert Ok(validated) =
    tadpole.validate(tadpole.new(
      "tadpole_test_bot_token_value.a1b2c3.real_enough_for_structure_checks",
    ))

  validated.config.token
  |> should.equal(
    "tadpole_test_bot_token_value.a1b2c3.real_enough_for_structure_checks",
  )
}

pub fn privileged_intents_requested_reports_test() {
  let config =
    tadpole.new(
      "tadpole_test_bot_token_value.a1b2c3.real_enough_for_structure_checks",
    )
    |> tadpole.with_intents(
      intent.new()
      |> intent.enable(intent.GuildMessages)
      |> intent.enable(intent.MessageContent),
    )

  // Validation does NOT fail on privileged intents (Discord enforces at
  // Identify); Tadpole reports them so the caller can warn.
  let assert Ok(_) = tadpole.validate(config)
  tadpole.privileged_intents_requested(config)
  |> list.contains(intent.MessageContent)
  |> should.be_true
}

pub fn no_privileged_intents_reports_empty_test() {
  let config =
    tadpole.new("token")
    |> tadpole.with_intents(intent.new() |> intent.enable(intent.GuildMessages))

  tadpole.privileged_intents_requested(config)
  |> list.length
  |> should.equal(0)
}

pub fn describe_config_redacts_token_test() {
  let token = "MTIzNDU2Nzg5MDEyMzQ1Njc4OTAxMjM0NTY3ODkwMTIzNDU2Nzg5"
  let described = tadpole.describe_config(tadpole.new(token))

  // The full token must never appear in the description.
  string.contains(described, token) |> should.be_false
  string.contains(described, "...") |> should.be_true
}

pub fn describe_config_mentions_shards_and_intents_test() {
  let config =
    tadpole.new("MTIzNDU2Nzg5MDEyMzQ1Njc4OTAxMjM0NTY3ODkwMTIzNDU2Nzg5")
    |> tadpole.with_shards(3)
    |> tadpole.with_intents(intent.new() |> intent.enable(intent.GuildMessages))

  let described = tadpole.describe_config(config)
  string.contains(described, "3 shard(s)") |> should.be_true
  string.contains(described, "GUILD_MESSAGES") |> should.be_true
}

pub fn intents_are_composable_test() {
  let intents =
    intent.new()
    |> intent.enable(intent.Guilds)
    |> intent.enable(intent.GuildMessages)
    |> intent.enable(intent.MessageContent)

  intent.has(intents, intent.Guilds) |> should.be_true
  intent.has(intents, intent.GuildMessages) |> should.be_true
  intent.has(intents, intent.MessageContent) |> should.be_true
}
