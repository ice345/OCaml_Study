open Lwt.Syntax

module type PLATFORM = sig
  module Block : Block.BLOCK
  module Net : Net.NETWORK
  module Clock : Clock.S
  module Random : Nano_random.S
end

module Make (P : PLATFORM) = struct
  module Fs_impl = Fs.Make (P.Block)
  module Stack_impl = Stack.Make (P.Net) (P.Clock) (P.Random)
  module Kernel = Unikernel.Make (Fs_impl) (Stack_impl)

  let boot_with_devices
      ?(stack_config = Stack.default_config)
      ~disk
      ~net
      ~clock
      ~random
      ~port
      () =
    let* fs = Fs_impl.connect ~repair:true disk in
    let* formatted = Fs_impl.is_formatted fs in
    let* () =
      if formatted then Lwt.return_unit
      else
        let* _ = Fs_impl.format fs in
        Lwt.return_unit
    in
    let stack = Stack_impl.create ~config:stack_config ~net ~clock ~random ~my_port:port in
    Kernel.run fs stack

  let boot ?(stack_config = Stack.default_config) ~disk ~port () =
    let* disk_dev = P.Block.connect disk in
    let* net = P.Net.connect port in
    let* clock = P.Clock.connect () in
    let* random = P.Random.connect () in
    let port_i = int_of_string port in
    boot_with_devices ~stack_config ~disk:disk_dev ~net ~clock ~random ~port:port_i ()
end
