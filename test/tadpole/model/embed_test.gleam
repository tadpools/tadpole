import gleam/json
import gleam/option.{Some}
import gleam/string
import gleeunit/should
import tadpole/model/embed

pub fn to_json_embed_test() {
  let embed = embed.Embed(..embed.new(), title: Some("t"))
  let rendered = json.to_string(embed.to_json(embed))
  { string.contains(rendered, "\"title\":\"t\"") } |> should.be_true
}
