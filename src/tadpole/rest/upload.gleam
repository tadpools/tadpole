//// Multipart form-data helpers for file uploads.
//// Stability: Experimental.

import gleam/bit_array
import gleam/int
import gleam/list
import tadpole/model/file.{type File}

pub fn build_multipart(payload_json: String, files: List(File)) -> BitArray {
  let boundary = "----tadpoleboundary"
  let mut =
    bit_array.from_string(
      "--"
      <> boundary
      <> "\r\n"
      <> "Content-Disposition: form-data; name=\"payload_json\"\r\n"
      <> "Content-Type: application/json\r\n\r\n"
      <> payload_json
      <> "\r\n",
    )
  let mut =
    list.index_fold(files, mut, fn(acc, f, i) {
      let part =
        "--"
        <> boundary
        <> "\r\n"
        <> "Content-Disposition: form-data; name=\"files["
        <> int.to_string(i)
        <> "]\"; filename=\""
        <> f.name
        <> "\"\r\n"
        <> "Content-Type: "
        <> f.mime_type
        <> "\r\n\r\n"
      bit_array.append(acc, bit_array.from_string(part))
      |> bit_array.append(f.content)
      |> bit_array.append(bit_array.from_string("\r\n"))
    })
  bit_array.append(mut, bit_array.from_string("--" <> boundary <> "--\r\n"))
}
