open Lwt.Syntax
open Nano_os
open Nano_os_unix

module UnixApp = App.Make (Platform_unix)

let boot () =
  let* () = Lwt_io.printl "=== NanoOS Booting ===" in
  let stack_cfg =
    {
      Stack.max_retries = 6;
      initial_timeout_s = 0.2;
      max_timeout_s = 2.0;
      timeout_jitter_s = 0.05;
      dedupe_window_s = 30.0;
    }
  in
  let* () = Lwt_io.printl "[Driver] Platform: unix (file_disk + socket_net + clock + random)" in
  let* () = Lwt_io.printl "[Driver] Network Up (UDP :8080)" in
  UnixApp.boot ~stack_config:stack_cfg ~disk:"nano_disk.img" ~port:"8080" ()

let () = Lwt_main.run (boot ())
