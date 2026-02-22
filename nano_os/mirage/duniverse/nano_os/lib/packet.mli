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

val header_len : int

val encode_data : seq:int -> src_port:int -> payload:string -> Cstruct.t
val encode_ack : ack:int -> src_port:int -> Cstruct.t

val decode : Cstruct.t -> (t, decode_error) result

val pp_decode_error : Format.formatter -> decode_error -> unit
