module type S = sig
  type t

  val connect : unit -> t Lwt.t
  val int : t -> int -> int
  val float : t -> float -> float
end
