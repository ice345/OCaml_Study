type error =
  [ `Block_error of Block.error
  | `File_not_found of string
  | `File_exists of string
  | `No_space
  | `Corrupt_filesystem
  ]

val pp_error : Format.formatter -> error -> unit

module type S = sig
  type t
  type block_t

  val format : t -> (unit, error) result Lwt.t
  val create_file : t -> string -> string -> (unit, error) result Lwt.t
  val write_file : t -> string -> string -> (unit, error) result Lwt.t
  val read_file : t -> string -> (string, error) result Lwt.t
  val ls : t -> string list Lwt.t
  val delete_file : t -> string -> (unit, error) result Lwt.t

  val connect : ?repair:bool -> block_t -> t Lwt.t
  val is_formatted : t -> bool Lwt.t
end

module Make (B : Block.BLOCK) : S with type block_t = B.t
