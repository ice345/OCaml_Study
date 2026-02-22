type kind = Data | Ack

type t = {
  version : int;
  kind : kind;
  seq : int;
  ack : int;
  src_port : int;
  payload : string;
}

type decode_error =
  [ `Truncated of int
  | `Bad_version of int
  | `Bad_kind of int
  | `Length_mismatch of int * int
  | `Checksum_mismatch of int * int
  ]

let pp_decode_error ppf = function
  | `Truncated len -> Fmt.pf ppf "Packet too short: %d" len
  | `Bad_version v -> Fmt.pf ppf "Unsupported packet version: %d" v
  | `Bad_kind k -> Fmt.pf ppf "Unsupported packet kind: %d" k
  | `Length_mismatch (declared, actual) ->
      Fmt.pf ppf "Length mismatch (declared=%d actual=%d)" declared actual
  | `Checksum_mismatch (declared, computed) ->
      Fmt.pf ppf "Checksum mismatch (declared=%d computed=%d)" declared computed

let version = 1
let header_len = 10

let int_of_kind = function Data -> 0 | Ack -> 1

let kind_of_int = function
  | 0 -> Ok Data
  | 1 -> Ok Ack
  | k -> Error (`Bad_kind k)

let checksum_bytes (bytes : bytes) =
  let sum = ref 0 in
  for i = 0 to Bytes.length bytes - 1 do
    sum := (!sum + Char.code (Bytes.get bytes i)) land 0xFFFF
  done;
  !sum

let checksum_from_parts ~version ~kind ~seq ~ack ~src_port ~payload =
  let payload_len = String.length payload in
  let buf = Cstruct.create (header_len - 2 + payload_len) in
  Cstruct.set_uint8 buf 0 version;
  Cstruct.set_uint8 buf 1 kind;
  Cstruct.set_uint8 buf 2 seq;
  Cstruct.set_uint8 buf 3 ack;
  Cstruct.LE.set_uint16 buf 4 src_port;
  Cstruct.LE.set_uint16 buf 6 payload_len;
  Cstruct.blit_from_string payload 0 buf 8 payload_len;
  checksum_bytes (Cstruct.to_bytes buf)

let encode ~kind ~seq ~ack ~src_port ~payload =
  let payload_len = String.length payload in
  let total_len = header_len + payload_len in
  let buf = Cstruct.create total_len in
  let kind_int = int_of_kind kind in
  let checksum =
    checksum_from_parts ~version ~kind:kind_int ~seq ~ack ~src_port ~payload
  in
  Cstruct.set_uint8 buf 0 version;
  Cstruct.set_uint8 buf 1 kind_int;
  Cstruct.set_uint8 buf 2 seq;
  Cstruct.set_uint8 buf 3 ack;
  Cstruct.LE.set_uint16 buf 4 src_port;
  Cstruct.LE.set_uint16 buf 6 payload_len;
  Cstruct.LE.set_uint16 buf 8 checksum;
  Cstruct.blit_from_string payload 0 buf header_len payload_len;
  buf

let encode_data ~seq ~src_port ~payload =
  encode ~kind:Data ~seq ~ack:0 ~src_port ~payload

let encode_ack ~ack ~src_port =
  encode ~kind:Ack ~seq:0 ~ack ~src_port ~payload:""

let decode packet =
  let len = Cstruct.length packet in
  if len < header_len then Error (`Truncated len)
  else
    let packet_version = Cstruct.get_uint8 packet 0 in
    if packet_version <> version then Error (`Bad_version packet_version)
    else
      let kind_int = Cstruct.get_uint8 packet 1 in
      match kind_of_int kind_int with
      | Error e -> Error e
      | Ok kind ->
          let seq = Cstruct.get_uint8 packet 2 in
          let ack = Cstruct.get_uint8 packet 3 in
          let src_port = Cstruct.LE.get_uint16 packet 4 in
          let declared_len = Cstruct.LE.get_uint16 packet 6 in
          let declared_checksum = Cstruct.LE.get_uint16 packet 8 in
          let actual_payload_len = len - header_len in
          if declared_len <> actual_payload_len then
            Error (`Length_mismatch (declared_len, actual_payload_len))
          else
            let payload = Cstruct.to_string (Cstruct.sub packet header_len declared_len) in
            let computed_checksum =
              checksum_from_parts
                ~version:packet_version
                ~kind:kind_int
                ~seq
                ~ack
                ~src_port
                ~payload
            in
            if computed_checksum <> declared_checksum then
              Error
                (`Checksum_mismatch (declared_checksum, computed_checksum))
            else Ok { version = packet_version; kind; seq; ack; src_port; payload }
