type config = {
  max_retries : int;
  initial_timeout_s : float;
  max_timeout_s : float;
  timeout_jitter_s : float;
  dedupe_window_s : float;
}

val default_config : config

module type S = sig
  type t
  type net_t
  type clock_t
  type random_t

  val create :
    config:config -> net:net_t -> clock:clock_t -> random:random_t -> my_port:int -> t

  val connect : ?config:config -> string -> t Lwt.t
  val send : t -> int -> string -> (unit, Net.error) result Lwt.t
  val listen : t -> (int -> string -> unit Lwt.t) -> (unit, Net.error) result Lwt.t
end

module Make
    (N : Net.NETWORK)
    (C : Clock.S)
    (R : Nano_random.S) :
  S with type net_t = N.t and type clock_t = C.t and type random_t = R.t
