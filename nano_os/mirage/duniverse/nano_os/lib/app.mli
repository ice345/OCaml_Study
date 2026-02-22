module type PLATFORM = sig
  module Block : Block.BLOCK
  module Net : Net.NETWORK
  module Clock : Clock.S
  module Random : Nano_random.S
end

module Make (P : PLATFORM) : sig
  module Fs_impl : Fs.S with type block_t = P.Block.t

  module Stack_impl :
    Stack.S
      with type net_t = P.Net.t
       and type clock_t = P.Clock.t
       and type random_t = P.Random.t

  module Kernel : Unikernel.RUNNER with type fs_t = Fs_impl.t and type net_t = Stack_impl.t

  val boot : ?stack_config:Stack.config -> disk:string -> port:string -> unit -> unit Lwt.t

  val boot_with_devices :
    ?stack_config:Stack.config ->
    disk:P.Block.t ->
    net:P.Net.t ->
    clock:P.Clock.t ->
    random:P.Random.t ->
    port:int ->
    unit ->
    unit Lwt.t
end
