open Lwt.Syntax

let sleep_and_print n =
  let* () = Lwt_unix.sleep (float_of_int n *. 0.1) in
  Lwt_io.printf "Slept for %d ms\n" n

let sleep_sort nums =
  Lwt_list.iter_p (fun x -> sleep_and_print x) nums

let () =
  Lwt_main.run (
    let nums = [30; 10; 20; 40; 50] in
    sleep_sort nums
  )
