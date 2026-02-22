open Lwt.Syntax
open Nano_os
open Nano_os_unix

module ClientStack = Stack.Make (Socket_net) (Clock_unix) (Random_unix)

let main () =
  let cfg =
    {
      Stack.max_retries = 4;
      initial_timeout_s = 0.1;
      max_timeout_s = 1.0;
      timeout_jitter_s = 0.02;
      dedupe_window_s = 10.0;
    }
  in
  let* stack = ClientStack.connect ~config:cfg "1234" in
  let* () = Lwt_io.printl "[Client] Network Up (UDP :1234)" in

  let response_handler src msg = Lwt_io.printlf "<< Received from %d:\n%s\n" src msg in
  Lwt.async (fun () ->
      let* _ = ClientStack.listen stack response_handler in
      Lwt.return_unit);

  let server_port = 8080 in

  let* () = Lwt_io.printl "--- NanoOS Client Shell ---" in
  let* () = Lwt_io.printl "Type 'help' for commands, 'exit' to quit." in

  let rec repl () =
    let* () = Lwt_io.print "> " in
    let* input = Lwt_io.read_line Lwt_io.stdin in
    if input = "exit" then Lwt.return_unit
    else
      let* send_res = ClientStack.send stack server_port input in
      let* () =
        match send_res with
        | Ok () -> Lwt.return_unit
        | Error e ->
            Lwt_io.printl ("[Client] send failed: " ^ Format.asprintf "%a" Nano_os.Net.pp_error e)
      in
      let* () = Lwt_unix.sleep 0.2 in
      repl ()
  in
  repl ()

let () = Lwt_main.run (main ())
