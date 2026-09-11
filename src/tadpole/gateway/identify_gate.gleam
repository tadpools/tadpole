//// Identify pacing across a shard fleet. Discord allows roughly one
//// IDENTIFY per 5 seconds per guild bucket and reports the real budget
//// as `max_concurrency` on GET /gateway/bot. Fetching that value is a
//// later milestone; until then the pacing lives here as documentation
//// and a conservative default. A fleet that ignores it meets close code
//// 4005 (already authenticated) or session-start-limit 429s.
////
//// ## When you reach for this
////
//// When you build a multi-shard fleet — call `identify_delay_ms` to get
//// the wait between consecutive IDENTIFYs. Not wired into anything yet;
//// [`tadpole/bot`](../bot.html) runs one shard, which never needs
//// pacing.
////
//// Stability: Experimental.
////
//// Not wired into anything yet — [`tadpole/bot`](../bot.html) runs one
//// shard, which never needs pacing. The one function is pure math for
//// the fleet code to come; see also [`tadpole/gateway`](../gateway.html).

const identify_interval_ms = 5000

/// Milliseconds to wait between IDENTIFYs when starting `shard_count`
/// shards from one process, assuming the worst case of a single guild
/// bucket. Large bots (max_concurrency > 1) can safely go faster once
/// /gateway/bot is wired up; small fleets cannot go faster than one
/// identify per 5 seconds at all.
pub fn recommended_delay_ms(shard_count: Int) -> Int {
  case shard_count < 1 {
    True -> identify_interval_ms
    False -> shard_count * identify_interval_ms
  }
}
