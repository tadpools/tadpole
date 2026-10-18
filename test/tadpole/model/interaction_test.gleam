import gleam/option.{Some}
import gleeunit/should
import tadpole/model/interaction
import tadpole/types/ids

const sample = "{\"id\":\"900000000000000001\",\"application_id\":\"900000000000000002\",\"type\":2,\"token\":\"tok\",\"channel_id\":\"900000000000000003\",\"guild_id\":\"900000000000000004\",\"user\":{\"id\":\"900000000000000005\"},\"data\":{\"name\":\"ping\",\"options\":[{\"name\":\"msg\",\"value\":\"hi\"}]}}"

pub fn from_json_full_interaction_test() {
  let assert Ok(parsed) = interaction.from_json(sample)
  ids.interaction_to_string(parsed.id) |> should.equal("900000000000000001")
  ids.application_to_string(parsed.application_id)
  |> should.equal("900000000000000002")
  parsed.token |> should.equal("tok")
  let assert Some(uid) = parsed.user_id
  ids.user_to_string(uid) |> should.equal("900000000000000005")
  let assert Some(d) = parsed.data
  d.name |> should.equal("ping")
}
