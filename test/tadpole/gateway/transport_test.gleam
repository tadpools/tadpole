//// Offline transport tests only. Real connections are exercised by the
//// live smoke run (dev/smoke_gw), never in the unit suite — no fake
//// stratus, no sockets here. What can be checked without a network is
//// URL validation: a config typo should fail before any handshake.

import gleam/http.{Http, Https}
import gleam/option.{None, Some}
import gleeunit/should
import tadpole/error.{BadRequest, GatewayConnectFailed}
import tadpole/gateway/transport
import tadpole/user_agent

pub fn wss_url_builds_tls_request_test() {
  let assert Ok(req) =
    transport.gateway_request("wss://gateway.discord.gg/?v=10&encoding=json")
  req.scheme |> should.equal(Https)
  req.host |> should.equal("gateway.discord.gg")
  req.path |> should.equal("/")
  req.query |> should.equal(Some("v=10&encoding=json"))
  req.port |> should.equal(None)
}

pub fn handshake_carries_the_user_agent_test() {
  // Discord requires the DiscordBot ($url, $versionNumber) shape on
  // HTTP API requests; the websocket upgrade is an HTTP request too,
  // so it gets the same identification.
  let assert Ok(req) =
    transport.gateway_request("wss://gateway.discord.gg/?v=10&encoding=json")
  req.headers
  |> should.equal([user_agent.header()])
}

pub fn ws_url_builds_plain_request_test() {
  let assert Ok(req) = transport.gateway_request("ws://localhost:8080/gw")
  req.scheme |> should.equal(Http)
  req.host |> should.equal("localhost")
  req.path |> should.equal("/gw")
  req.port |> should.equal(Some(8080))
}

pub fn http_schemes_are_rejected_test() {
  // The gateway is always a websocket; an http(s) URL is a config error
  // masquerading as a transport choice.
  transport.gateway_request("https://gateway.discord.gg")
  |> should.equal(Error(GatewayConnectFailed(BadRequest, 0, 0)))
  transport.gateway_request("http://gateway.discord.gg")
  |> should.equal(Error(GatewayConnectFailed(BadRequest, 0, 0)))
}

pub fn unparseable_urls_are_rejected_test() {
  transport.gateway_request("not a url") |> should.be_error
  transport.gateway_request("") |> should.be_error
}

pub fn urls_without_a_host_are_rejected_test() {
  transport.gateway_request("wss://") |> should.be_error
}
