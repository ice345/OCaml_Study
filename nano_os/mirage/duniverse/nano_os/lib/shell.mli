module type S = sig
  type t
  val eval : t -> string -> string Lwt.t
end

module Make (F : Fs.S) : S with type t = F.t
