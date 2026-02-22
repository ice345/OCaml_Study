open Lwt.Syntax

module type RUNNER = sig
  type fs_t
  type net_t

  val run : fs_t -> net_t -> unit Lwt.t
end

module Make (Fs_mod : Fs.S) (Stack_mod : Stack.S) = struct
  module Shell_mod = Shell.Make (Fs_mod)

  type fs_t = Fs_mod.t
  type net_t = Stack_mod.t

  let run fs net_dev =
    let* listen_res =
      Stack_mod.listen net_dev (fun port payload ->
          (* Handle each request asynchronously so the listener keeps running. *)
          Lwt.async (fun () ->
            let* response = Shell_mod.eval fs payload in
            let* send_res = Stack_mod.send net_dev port response in
            match send_res with
            | Ok () -> Lwt.return_unit
            | Error _ -> Lwt.return_unit);
          Lwt.return_unit)
    in
    match listen_res with
    | Ok () -> Lwt.return_unit
    | Error _ -> Lwt.return_unit
end
