open Nano_os

type t = unit

let connect () = Lwt.return_unit
let sleep_s () seconds = Lwt_unix.sleep seconds
let now_ns () = Int64.of_float (Unix.gettimeofday () *. 1_000_000_000.0)

module _ : Clock.S with type t = t = struct
  type nonrec t = t

  let connect = connect
  let sleep_s = sleep_s
  let now_ns = now_ns
end
