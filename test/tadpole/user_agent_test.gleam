//// Tests for the User-Agent tadpole sends to Discord.
////
//// The format is not our choice: Discord's reference docs require
//// `DiscordBot ($url, $versionNumber)` on HTTP API requests and warn
//// that clients without a valid one may be blocked by Cloudflare.
//// These tests pin that contract so a refactor cannot quietly break
//// identification.

import gleam/string
import gleeunit/should
import tadpole/user_agent

pub fn value_matches_discord_required_format_test() {
  user_agent.value()
  |> should.equal("DiscordBot (https://github.com/tadpools/tadpole, 2026.3.0)")
}

pub fn header_pair_uses_lowercase_name_test() {
  let assert #("user-agent", value) = user_agent.header()
  value |> should.equal(user_agent.value())
}

pub fn url_and_version_appear_in_value_test() {
  let v = user_agent.value()
  { v |> string.contains(user_agent.repo_url) }
  |> should.be_true
  { v |> string.contains(user_agent.version) }
  |> should.be_true
}
