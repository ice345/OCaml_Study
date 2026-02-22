module type RUNNER = sig
  type fs_t
  type net_t

  val run : fs_t -> net_t -> unit Lwt.t
end

module Make (Fs_mod : Fs.S) (Stack_mod : Stack.S) :
  RUNNER with type fs_t = Fs_mod.t and type net_t = Stack_mod.t
