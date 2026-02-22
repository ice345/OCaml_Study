type error = [
  | `Disconnected
  | `Is_read_only
  | `Out_of_bounds of int64
]

val pp_error : Format.formatter -> error -> unit

type info = {
  size_sectors : int64;
  sector_size : int;
  read_write : bool;
}

module type BLOCK = sig
  type t

  type write_error = error
  type read_error = error

  val get_info : t -> info Lwt.t
  val read : t -> int64 -> Cstruct.t list -> (unit, read_error) result Lwt.t
  val write : t -> int64 -> Cstruct.t list -> (unit, write_error) result Lwt.t

  val connect : string -> t Lwt.t
  val disconnect : t -> unit Lwt.t
end
