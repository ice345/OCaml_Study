open Nano_os

type t = Stdlib.Random.State.t

let connect () = Lwt.return (Stdlib.Random.State.make_self_init ())
let int state bound = Stdlib.Random.State.int state bound
let float state bound = Stdlib.Random.State.float state bound

module _ : Random.S with type t = t = struct
  type nonrec t = t

  let connect = connect
  let int = int
  let float = float
end
