//// The REST executor: turns RestRequests into responses over an injected
//// transport. Tests run against canned `gleam/http` values; the Erlang
//// target ships gleam_httpc. Rate-limit behaviour is learned from
//// response headers and 429 bodies only (see tadpole/rest/rate_limit)
//// and applied as best-effort waits before sending.
////
//// Transport failures surface as RestStatus with the synthetic status 0
//// and a "no HTTP response: ..." body. No variant in error.gleam
//// describes a REST transport failure honestly — GatewayConnectFailed
//// means gateway reconnects — and status 0 reads as "no HTTP happened"
//// anywhere a status is printed.
////
//// ## When you reach for this
////
//// Behind [`tadpole/rest/endpoints`](endpoints.html) for the known
//// calls; directly when you need a Discord route the endpoint helpers
//// do not wrap, or when one run of calls should share rate-limit state
//// (`send_in_session`). Tests reach for it constantly: `Transport` is
//// one function.
////
//// ## Transport injection
////
//// `Transport` is
//// `fn(Request(String)) -> Result(Response(String), TransportError)` —
//// the executor knows nothing else about HTTP. `httpc_transport`
//// wraps gleam_httpc for production; tests hand in a closure returning
//// canned responses; a future JS target would hand in fetch. The
//// TransportError shapes mirror gleam_httpc 5.x's `HttpError`
//// one-to-one, so nothing is lost in translation and other transports
//// map onto the same three cases.
////
//// ## The status-0 convention
////
//// When the transport fails — no connection, timeout, non-UTF-8 body —
//// no HTTP response exists to report. Rather than stretch a variant,
//// the failure becomes `error.RestStatus` with `status: 0`,
//// `discord_code: None`, and the transport's own description in the
//// body: `"no HTTP response: failed to connect (ipv4: ..., ipv6: ...)"`.
//// Matching `RestStatus(_, 0, _, _)` catches every "Discord never saw
//// this request" case.
////
//// ## send, send_with_sleep, send_in_session
////
//// - `send` — one request, throwaway rate-limit state: waits learned
////   during this call throttle only this call's own 429 retries, and
////   nothing carries to the next call. What the endpoint helpers use.
//// - `send_with_sleep` — `send` with the sleep function injected;
////   tests pass a recorder instead of waiting real milliseconds.
//// - `send_in_session` — the request runs inside a `RestSession`, so a
////   wait learned from one response gates the next call on the same
////   route. Returns the updated session; thread it through your loop.
////
//// ## 429 retry flow
////
//// On a 429: fold the response into the session, then, if the client
//// has `retry_on_429` and attempts remain, sleep the window the
//// response asked for — the `Retry-After` header (whole seconds, to ms)
//// first, else the body's fractional `retry_after` — and try again.
//// When retries run out, the error is `error.RateLimited` carrying the
//// route, the last window in ms, the global flag, and the bucket id.
//// Zero-window 429s retry immediately. Sleeps are real
//// `process.sleep`: the calling process waits.
////
//// ## RestSession ownership honesty
////
//// A `RestSession` is a plain value, not a process. Passing it to two
//// processes gives each an independent copy — no cross-process
//// coordination, and no corruption either. The executor owns no clock:
//// a wait is measured as time elapsed since the response that produced
//// it, so a session reused long after real time passed waits slightly
//// long. That errs safe.
////
//// ## Concurrency
////
//// - `send` and `send_with_sleep` share nothing between calls: safe
////   from as many processes as you like.
//// - A session threaded through one process serializes that route's
////   calls — that is the point. A session sent across processes is
////   copied per message; learned waits diverge silently.
//// - Every sleep blocks the calling process: pre-send waits, 429
////   windows, and the HTTP round trip (bounded by the client timeout).
////
//// ## Failure modes
////
//// `RestStatus` for any non-2xx (status 0 = transport failure) and
//// `RateLimited` when 429s outlast the retries. Nothing else: the body
//// is returned raw, so no `DecodeFailed` here — decoding is the
//// endpoint's job. Never panics, and the token never appears in an
//// error.
////
//// ## See also
////
//// - [`tadpole/rest/rate_limit`](rate_limit.html) — the pure state behind the waits
//// - [`tadpole/rest`](../rest.html) — request builders and header parsing
//// - [`tadpole/rest/endpoints`](endpoints.html) — the endpoint helpers on top

import gleam/dict
import gleam/dynamic/decode as d
import gleam/erlang/process
import gleam/float
import gleam/http
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/httpc
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import gleam/uri
import tadpole/error.{type BucketId, type TadpoleError}
import tadpole/rest
import tadpole/rest/rate_limit

/// What a transport can fail with. The shapes mirror gleam_httpc 5.x's
/// `HttpError` one-to-one — the only transport shipped here — so nothing
/// is lost in translation and a different transport maps onto the same
/// three cases.
pub type TransportError {
  /// The response body was not valid UTF-8, so it could not be read as text.
  InvalidUtf8Response
  /// No connection could be established: the IPv4 and the IPv6 attempt
  /// each failed with their own detail.
  FailedToConnect(ip4: ConnectError, ip6: ConnectError)
  /// No response arrived within the client's timeout.
  ResponseTimeout
}

pub type ConnectError {
  /// An OS-level connect failure, e.g. "econnrefused" or "nxdomain".
  Posix(code: String)
  /// The TLS handshake was refused; code and detail name the alert.
  TlsAlert(code: String, detail: String)
}

/// A function that performs HTTP. The executor only knows this shape, so
/// tests hand in canned responses and a future JS target can hand in
/// fetch without this module caring.
pub type Transport =
  fn(Request(String)) -> Result(Response(String), TransportError)

const api_prefix = "/api/v10"

const user_agent = "tadpole (Gleam Discord library)"

/// The real transport, on gleam_httpc. `timeout_ms` bounds how long one
/// request may take; Discord calls regularly run past a second, so a
/// 30s timeout (the httpc default) is a sensible client setting.
pub fn httpc_transport(timeout_ms: Int) -> Transport {
  let config = httpc.configure() |> httpc.timeout(timeout_ms)
  fn(request) {
    case httpc.dispatch(config, request) {
      Ok(response) -> Ok(response)
      Error(httpc.InvalidUtf8Response) -> Error(InvalidUtf8Response)
      Error(httpc.FailedToConnect(ip4, ip6)) ->
        Error(FailedToConnect(to_connect_error(ip4), to_connect_error(ip6)))
      Error(httpc.ResponseTimeout) -> Error(ResponseTimeout)
    }
  }
}

fn to_connect_error(e: httpc.ConnectError) -> ConnectError {
  case e {
    httpc.Posix(code) -> Posix(code)
    httpc.TlsAlert(code, detail) -> TlsAlert(code, detail)
  }
}

/// Human-readable form, used in the RestStatus body a transport failure
/// becomes. Never contains the token.
pub fn transport_error_to_string(transport_error: TransportError) -> String {
  case transport_error {
    InvalidUtf8Response -> "response body was not valid UTF-8"
    FailedToConnect(ip4, ip6) ->
      "failed to connect (ipv4: "
      <> connect_error_to_string(ip4)
      <> ", ipv6: "
      <> connect_error_to_string(ip6)
      <> ")"
    ResponseTimeout -> "no response within the client timeout"
  }
}

fn connect_error_to_string(connect_error: ConnectError) -> String {
  case connect_error {
    Posix(code) -> code
    TlsAlert(code, detail) -> code <> " " <> detail
  }
}

/// Rate-limit bookkeeping for a run of calls: the client, the observed
/// bucket states, and the route -> bucket bindings. A plain value, not a
/// process — passing it to two processes gives each its own copy, and
/// cross-process coordination is future work.
///
/// States are keyed by the masked route key until a response names a
/// bucket, then by that bucket id, as rate_limit.associate describes.
pub type RestSession {
  RestSession(
    client: rest.RestClient,
    buckets: dict.Dict(String, rate_limit.BucketState),
    routes: dict.Dict(String, BucketId),
  )
}

/// A session with no observed limits yet.
pub fn new_session(client: rest.RestClient) -> RestSession {
  RestSession(client: client, buckets: dict.new(), routes: dict.new())
}

/// Execute one request against Discord's API. Sleeps are real
/// (gleam/erlang/process.sleep): 429 retries and pre-send waits block the
/// calling process.
///
/// State is per call: the rate-limit bookkeeping lives only as long as
/// this request, so learned waits throttle this request's own retries
/// and nothing carries to the next call. Beginner bots do one call at a
/// time; to share bucket state across a run of calls, use `new_session`
/// with `send_in_session`.
///
/// Fails with RestStatus for any non-2xx (status 0 means the transport
/// never got a response), DecodeFailed is not raised here — the body is
/// returned raw — and RateLimited once 429s outlast the configured
/// retries. Never panics; the token never appears in an error.
pub fn send(
  client: rest.RestClient,
  request: rest.RestRequest,
  transport: Transport,
) -> Result(rest.RestResponse, TadpoleError) {
  send_with_sleep(client, request, transport, process.sleep)
}

/// Same as `send` with the sleep function injected: tests pass a no-op
/// that records durations instead of waiting.
pub fn send_with_sleep(
  client: rest.RestClient,
  request: rest.RestRequest,
  transport: Transport,
  sleep_fn: fn(Int) -> Nil,
) -> Result(rest.RestResponse, TadpoleError) {
  let #(result, _) =
    send_in_session(new_session(client), request, transport, sleep_fn)
  result
}

/// Execute a request inside a session, so waits learned from one
/// response gate the next call on the same route.
///
/// The executor owns no clock: a wait is measured from the response that
/// produced it, as if that response had just arrived. A session reused
/// after real time has passed can therefore wait slightly long — that
/// errs safe. The first call on an unknown route always sends
/// immediately; limits are discovered, not predicted.
pub fn send_in_session(
  session: RestSession,
  request: rest.RestRequest,
  transport: Transport,
  sleep_fn: fn(Int) -> Nil,
) -> #(Result(rest.RestResponse, TadpoleError), RestSession) {
  let route =
    error.Route(method: to_route_method(request.method), path: request.path)
  let key =
    rate_limit.route_key(error.method_to_string(route.method), request.path)
  attempt(session, request, route, key, transport, sleep_fn, 0, 0)
}

/// One send round: gate, dispatch, record, then either done, retry, or
/// mapped error. `elapsed_ms` is time slept since the response that last
/// updated this route's bucket state — 0 right after `record`, the
/// window we slept after a 429.
fn attempt(
  session: RestSession,
  request: rest.RestRequest,
  route: error.Route,
  key: String,
  transport: Transport,
  sleep_fn: fn(Int) -> Nil,
  attempt_no: Int,
  elapsed_ms: Int,
) -> #(Result(rest.RestResponse, TadpoleError), RestSession) {
  let identity = current_identity(session, key)
  let wait = case dict.get(session.buckets, identity) {
    Ok(state) -> rate_limit.wait_ms(state, elapsed_ms)
    Error(_) -> 0
  }
  case wait > 0 {
    True -> sleep_fn(wait)
    False -> Nil
  }
  case transport(build_http_request(session.client, request)) {
    Error(transport_error) -> #(
      Error(transport_failure(route, transport_error)),
      session,
    )
    Ok(http_response) -> {
      let response = to_rest_response(http_response)
      let session = record(session, key, response)
      case response.status {
        429 ->
          retry_or_give_up(
            session,
            request,
            route,
            key,
            transport,
            sleep_fn,
            attempt_no,
            response,
          )
        status if status >= 200 && status < 300 -> #(Ok(response), session)
        _ -> #(Error(status_error(route, response)), session)
      }
    }
  }
}

fn retry_or_give_up(
  session: RestSession,
  request: rest.RestRequest,
  route: error.Route,
  key: String,
  transport: Transport,
  sleep_fn: fn(Int) -> Nil,
  attempt_no: Int,
  response: rest.RestResponse,
) -> #(Result(rest.RestResponse, TadpoleError), RestSession) {
  case session.client.retry_on_429 && attempt_no < session.client.max_retries {
    False -> #(Error(rate_limited_error(route, response)), session)
    True -> {
      let window = retry_window_ms(response)
      case window > 0 {
        True -> sleep_fn(window)
        False -> Nil
      }
      // the window was just slept against the state this response
      // produced, so it counts as elapsed on the next gate
      attempt(
        session,
        request,
        route,
        key,
        transport,
        sleep_fn,
        attempt_no + 1,
        window,
      )
    }
  }
}

/// Fold one response into the session: bind the bucket if the response
/// named one, update the state under the identity now in force.
fn record(
  session: RestSession,
  key: String,
  response: rest.RestResponse,
) -> RestSession {
  let routes = rate_limit.associate(session.routes, key, response)
  let identity = current_identity(RestSession(..session, routes: routes), key)
  let state = case dict.get(session.buckets, identity) {
    Ok(existing) -> rate_limit.update(existing, response)
    Error(_) -> rate_limit.update(rate_limit.new(), response)
  }
  RestSession(
    ..session,
    buckets: dict.insert(session.buckets, identity, state),
    routes: routes,
  )
}

fn current_identity(session: RestSession, key: String) -> String {
  case dict.get(session.routes, key) {
    Ok(bucket) -> error.bucket_id_to_string(bucket)
    Error(_) -> key
  }
}

fn to_rest_response(http_response: Response(String)) -> rest.RestResponse {
  rest.RestResponse(
    status: http_response.status,
    headers: http_response.headers,
    body: http_response.body,
    rate_limit_headers: Some(rest.parse_rate_limit_headers(
      http_response.headers,
    )),
  )
}

/// https://discord.com/api/v10 + the request path, with auth, UA, and
/// the optional body/reason headers. Header names go out lowercase:
/// gleam_http's convention, and gleam_httpc only suppresses its default
/// user-agent when it sees the exact name "user-agent".
fn build_http_request(
  client: rest.RestClient,
  request: rest.RestRequest,
) -> Request(String) {
  let headers =
    [
      rest.authorization_header(client.token),
      #("user-agent", user_agent),
      ..case request.body {
        Some(_) -> [#("content-type", "application/json")]
        None -> []
      }
    ]
    |> list.append(case request.audit_log_reason {
      Some(reason) -> [#("x-audit-log-reason", uri.percent_encode(reason))]
      None -> []
    })
    |> list.append(request.headers)
    |> list.map(fn(pair) { #(string.lowercase(pair.0), pair.1) })
  request.Request(
    method: to_http_method(request.method),
    headers: headers,
    body: option.unwrap(request.body, ""),
    scheme: http.Https,
    host: "discord.com",
    port: option.None,
    path: api_prefix <> request.path,
    query: option.None,
  )
}

fn to_http_method(method: rest.Method) -> http.Method {
  case method {
    rest.GET -> http.Get
    rest.POST -> http.Post
    rest.PUT -> http.Put
    rest.DELETE -> http.Delete
    rest.PATCH -> http.Patch
    rest.HEAD -> http.Head
    rest.OPTIONS -> http.Options
  }
}

fn to_route_method(method: rest.Method) -> error.HttpMethod {
  case method {
    rest.GET -> error.GET
    rest.POST -> error.POST
    rest.PUT -> error.PUT
    rest.DELETE -> error.DELETE
    rest.PATCH -> error.PATCH
    rest.HEAD -> error.HEAD
    rest.OPTIONS -> error.OPTIONS
  }
}

/// Transport failure convention: status 0, no Discord code, the failure
/// description in the body. See the module doc for why this and not an
/// existing variant.
fn transport_failure(
  route: error.Route,
  transport_error: TransportError,
) -> TadpoleError {
  error.RestStatus(
    route: route,
    status: 0,
    discord_code: None,
    body: Some(
      "no HTTP response: " <> transport_error_to_string(transport_error),
    ),
  )
}

/// Discord's error body is {"message": ..., "code": ...}; both fields may
/// be missing, and the raw body is kept either way.
fn status_error(
  route: error.Route,
  response: rest.RestResponse,
) -> TadpoleError {
  error.RestStatus(
    route: route,
    status: response.status,
    discord_code: body_code(response.body),
    body: Some(response.body),
  )
}

fn rate_limited_error(
  route: error.Route,
  response: rest.RestResponse,
) -> TadpoleError {
  let headers =
    option.unwrap(
      response.rate_limit_headers,
      rest.parse_rate_limit_headers([]),
    )
  error.RateLimited(
    route: route,
    retry_after_ms: retry_window_ms(response),
    is_global: headers.is_global || body_is_global(response.body),
    bucket: option.map(headers.bucket, error.bucket_id),
  )
}

/// The wait a 429 asked for, in ms: the Retry-After header (whole
/// seconds) first, then the body's retry_after — Discord sends that one
/// as a fractional number of seconds too — else 0, the same optimism
/// rate_limit.wait_ms shows when nothing is known.
fn retry_window_ms(response: rest.RestResponse) -> Int {
  case response.rate_limit_headers {
    Some(headers) ->
      case headers.retry_after {
        Some(seconds) -> seconds * 1000
        None -> body_retry_after_ms(response.body)
      }
    None -> body_retry_after_ms(response.body)
  }
}

/// Discord's 429 body: {"message": ..., "code": 429, "global": false,
/// "retry_after": 1.5}. retry_after is seconds despite sitting next to
/// ms-flavoured names; garbage or missing reads as no window.
fn body_retry_after_ms(body: String) -> Int {
  let decoder = {
    use retry_after <- d.optional_field(
      "retry_after",
      None,
      d.optional(d.one_of(d.float, or: [d.map(d.int, int.to_float)])),
    )
    d.success(retry_after)
  }
  case json.parse(body, decoder) {
    Ok(Some(seconds)) -> float.round(seconds *. 1000.0)
    _ -> 0
  }
}

fn body_code(body: String) -> Option(Int) {
  let decoder = {
    use code <- d.optional_field("code", None, d.optional(d.int))
    d.success(code)
  }
  case json.parse(body, decoder) {
    Ok(code) -> code
    Error(_) -> None
  }
}

fn body_is_global(body: String) -> Bool {
  let decoder = {
    use global <- d.optional_field("global", False, d.bool)
    d.success(global)
  }
  case json.parse(body, decoder) {
    Ok(global) -> global
    Error(_) -> False
  }
}
