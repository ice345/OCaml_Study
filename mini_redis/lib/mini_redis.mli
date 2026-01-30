(** Mini Redis Library Interface *)

type command
module Store : sig
  type t
  val create : unit -> t
end

val handle_request : Store.t -> string -> (string * string, string) result
