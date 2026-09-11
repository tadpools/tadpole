//// The User-Agent Discord requires on HTTP API requests, in the shape
//// `DiscordBot ($url, $versionNumber)` from their reference docs.
//// Requests without a valid one may be blocked by Cloudflare before
//// they ever reach the API. Both the REST transport and the gateway
//// websocket handshake send it, so Discord can tell a tadpole bot
//// from anything else in their logs.
////
//// ## When you reach for this
////
//// Through [`tadpole/rest/execute`](rest/execute.html) — the REST
//// client sends `user_agent_string` as the User-Agent header. Directly
//// when you need the version string (`version`) for logging or
//// diagnostics.
////
//// `version` is bumped by hand alongside gleam.toml as part of the
//// release checklist (CONTRIBUTING.md, release flow).
////
//// Stability: Stable.

/// The repository URL Discord sees in the User-Agent.
pub const repo_url = "https://github.com/tadpools/tadpole"

/// The tadpole version reported in the User-Agent. Keep in step with
/// gleam.toml at release time.
pub const version = "2026.3.0"

/// The full User-Agent value in Discord's required
/// `DiscordBot ($url, $versionNumber)` shape.
pub fn value() -> String {
  "DiscordBot (" <> repo_url <> ", " <> version <> ")"
}

/// The ready-made request header pair: ("user-agent", value).
pub fn header() -> #(String, String) {
  #("user-agent", value())
}
