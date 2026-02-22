type error = [ `Disconnected | `Unknown of string ]

let pp_error ppf = function
  | `Disconnected -> Fmt.string ppf "Network disconnected"
  | `Unknown s -> Fmt.pf ppf "Unknown error: %s" s

type stats = {
  rx_bytes : int64;
  tx_bytes : int64;
}

module type NETWORK = sig
  type t

  val connect : string -> t Lwt.t
  val disconnect : t -> unit Lwt.t

  val write : t -> dst:string -> Cstruct.t -> (unit, error) result Lwt.t
  val listen : t -> (Cstruct.t -> unit Lwt.t) -> (unit, error) result Lwt.t
end
