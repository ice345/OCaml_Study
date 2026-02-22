module type S = sig
  type t

  val connect : unit -> t Lwt.t
  val sleep_s : t -> float -> unit Lwt.t
  val now_ns : t -> int64
end
