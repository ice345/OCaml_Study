open Lwt.Syntax
open Unikv

module UnixClock :CLOCK = struct
  let now () =
    let timestamp = Unix.localtime (Unix.time ()) in
    Printf.sprintf "%04d-%02d-%02d %02d:%02d:%02d"
      (timestamp.Unix.tm_year + 1900)
      (timestamp.Unix.tm_mon + 1)
      timestamp.Unix.tm_mday
      timestamp.Unix.tm_hour
      timestamp.Unix.tm_min
      timestamp.Unix.tm_sec
end


module UnixConsole = struct
  let log msg =
    Lwt_io.printf "%s\n" msg
end

(* A mock clock for testing purposes *)
module MockClock : CLOCK = struct
  let now () = "2018-01-01 00:00:00"
end

(* A mock console for testing purposes *)
module MockConsole = struct
  let history = ref []

  let log msg =
    history := msg :: !history;
    Lwt.return_unit

  let get_history () = List.rev !history

  let clear_history () =
    history := []
end

module MyKV = MakeKV(UnixClock)(UnixConsole)
module TestKV = MakeKV(MockClock)(MockConsole)

let print_opt label = function
  | Some v -> Lwt_io.printf "%s: %s\n" label v
  | None -> Lwt_io.printf "%s: not found\n" label

let run_test () =
  let* () = Lwt_io.printf "--- Running Tests (Mock Mode) ---\n" in

  let kv_store = TestKV.create () in
  MockConsole.clear_history ();

  let* () = TestKV.set kv_store "test_key" "test_value" in

  let* val_opt = TestKV.get kv_store "test_key" in
  let* () = print_opt "test_key" val_opt in

  let logs = MockConsole.get_history () in
  let expected_log = "[2018-01-01 00:00:00] SET test_key = test_value" in

  match logs with
  | [actual_log] -> 
      if actual_log = expected_log then
        Lwt_io.printf "✅ Test Passed: Logs match exactly!\nLog entry is correct: %s\n" actual_log
      else
        Lwt_io.printf "❌ Test Failed:\nLog entry is incorrect. Expected: %s, Got: %s\n"
          expected_log actual_log
  | _ -> Lwt_io.printf "❌ Test Failed:\nUnexpected number of log entries: %d\n" (List.length logs)

let main () =
  let kv_store = MyKV.create () in

  let* () = Lwt_io.printf "--- System Started ---\n" in

  let* () = MyKV.set kv_store "username" "ice" in
  let* () = MyKV.set kv_store "status" "learning OCaml" in

  let* username_val = MyKV.get kv_store "username" in
  let* status_val   = MyKV.get kv_store "status" in

  let* () = print_opt "Username" username_val in
  let* () = print_opt "Status" status_val in

  run_test ()


let () =
  Lwt_main.run (main ())
