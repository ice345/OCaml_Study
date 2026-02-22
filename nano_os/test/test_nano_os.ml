open Lwt.Syntax
open Nano_os

module MyFS = FS.Make (RamDisk)
module MyShell = Shell.Make (MyFS)

let with_fs f =
  Lwt_main.run
    (let* disk = RamDisk.connect "test" in
     let* fs = MyFS.connect disk in
     let* format_res = MyFS.format fs in
     match format_res with
     | Error err -> Alcotest.failf "format failed: %a" FS.pp_error err
     | Ok () -> f fs)

let test_fs_create_and_read () =
  with_fs (fun fs ->
      let* create_res = MyFS.create_file fs "hello.txt" "nano-os" in
      (match create_res with
      | Error err -> Alcotest.failf "create failed: %a" FS.pp_error err
      | Ok () -> ());
      let* read_res = MyFS.read_file fs "hello.txt" in
      (match read_res with
      | Error err -> Alcotest.failf "read failed: %a" FS.pp_error err
      | Ok content -> Alcotest.(check string) "read content" "nano-os" content);
      Lwt.return_unit)

let test_fs_write_file_overwrites_atomically () =
  with_fs (fun fs ->
      let* first = MyFS.write_file fs "note.txt" "v1" in
      (match first with
      | Ok () -> ()
      | Error err -> Alcotest.failf "first write failed: %a" FS.pp_error err);
      let* second = MyFS.write_file fs "note.txt" "v2" in
      (match second with
      | Ok () -> ()
      | Error err -> Alcotest.failf "second write failed: %a" FS.pp_error err);
      let* read_res = MyFS.read_file fs "note.txt" in
      (match read_res with
      | Ok content -> Alcotest.(check string) "latest content" "v2" content
      | Error err -> Alcotest.failf "read failed: %a" FS.pp_error err);
      Lwt.return_unit)

let test_shell_write_overwrite () =
  with_fs (fun fs ->
      let* first = MyShell.eval fs "write note.txt first" in
      Alcotest.(check string) "first write" "File created successfully." first;
      let* second = MyShell.eval fs "write note.txt second" in
      Alcotest.(check string) "second write" "File overwritten successfully." second;
      let* cat = MyShell.eval fs "cat note.txt" in
      Alcotest.(check string) "overwritten content" "second" cat;
      Lwt.return_unit)

let test_shell_case_insensitive_commands () =
  with_fs (fun fs ->
      let* _ = MyShell.eval fs "WRITE Demo.txt payload" in
      let* list_output = MyShell.eval fs "LS" in
      let listed_files = String.split_on_char '\n' list_output in
      Alcotest.(check bool)
        "ls output contains filename"
        true
        (List.mem "Demo.txt" listed_files);
      let* cat_output = MyShell.eval fs "CAT Demo.txt" in
      Alcotest.(check string) "cat output" "payload" cat_output;
      Lwt.return_unit)

let test_shell_rm () =
  with_fs (fun fs ->
      let* _ = MyShell.eval fs "write temp value" in
      let* rm = MyShell.eval fs "rm temp" in
      Alcotest.(check string) "rm output" "File deleted." rm;
      let* cat = MyShell.eval fs "cat temp" in
      Alcotest.(check string) "cat after rm" "Error: File not found: temp" cat;
      Lwt.return_unit)

let test_packet_roundtrip () =
  let encoded = Packet.encode_data ~seq:7 ~src_port:1234 ~payload:"hello" in
  match Packet.decode encoded with
  | Error e -> Alcotest.failf "decode failed: %a" Packet.pp_decode_error e
  | Ok packet ->
      Alcotest.(check int) "version" 1 packet.version;
      Alcotest.(check int) "seq" 7 packet.seq;
      Alcotest.(check int) "src_port" 1234 packet.src_port;
      Alcotest.(check string) "payload" "hello" packet.payload

let test_packet_checksum_validation () =
  let encoded = Packet.encode_data ~seq:9 ~src_port:2222 ~payload:"abc" in
  Cstruct.set_uint8 encoded Packet.header_len (Char.code 'x');
  match Packet.decode encoded with
  | Error (`Checksum_mismatch _) -> ()
  | Error e -> Alcotest.failf "unexpected decode error: %a" Packet.pp_decode_error e
  | Ok _ -> Alcotest.fail "expected checksum mismatch"

let test_fs_connect_repairs_invalid_superblock () =
  Lwt_main.run
    (let* disk = RamDisk.connect "repair" in
     let super = Cstruct.create (5 * 512) in
     Cstruct.blit_from_string "NANO_FS\000" 0 super 0 8;
     Cstruct.LE.set_uint32 super 8 100l;
     Cstruct.LE.set_uint32 super 12 99999l;
     let* write_res = RamDisk.write disk 0L [ super ] in
     (match write_res with
     | Error err -> Alcotest.failf "raw write failed: %a" Block.pp_error err
     | Ok () -> ());
     let* fs = MyFS.connect ~repair:true disk in
     let* files = MyFS.ls fs in
     Alcotest.(check int) "repair dropped invalid entries" 0 (List.length files);
     let* create_res = MyFS.create_file fs "ok.txt" "1" in
     (match create_res with
     | Error err -> Alcotest.failf "create after repair failed: %a" FS.pp_error err
     | Ok () -> ());
     Lwt.return_unit)

module FakeClock : Clock.S = struct
  type t = unit

  let connect () = Lwt.return_unit
  let sleep_s () seconds = Lwt_unix.sleep seconds
  let now_ns () = Int64.of_float (Unix.gettimeofday () *. 1_000_000_000.0)
end

module FakeRandom : Random.S = struct
  type t = unit

  let connect () = Lwt.return_unit
  let int () bound = if bound <= 0 then 0 else 7 mod bound
  let float () bound = if bound <= 0.0 then 0.0 else bound *. 0.0
end

module FakeNet = struct
  type t = unit

  let listener : (Cstruct.t -> unit Lwt.t) option ref = ref None
  let auto_ack = ref false
  let writes = ref 0

  let reset ?(ack = false) () =
    listener := None;
    auto_ack := ack;
    writes := 0

  let writes_count () = !writes

  let connect _ = Lwt.return_unit
  let disconnect () = Lwt.return_unit

  let write () ~dst packet =
    incr writes;
    (if !auto_ack then
       match Packet.decode packet with
       | Ok { Packet.kind = Packet.Data; seq; _ } ->
           (match !listener with
           | Some cb ->
               let src_port = try int_of_string dst with _ -> 0 in
               let ack = Packet.encode_ack ~ack:seq ~src_port in
               Lwt.async (fun () -> cb ack)
           | None -> ())
       | _ -> ());
    Lwt.return (Ok ())

  let listen () callback =
    listener := Some callback;
    Lwt.return (Ok ())
end

module TestStack = Stack.Make (FakeNet) (FakeClock) (FakeRandom)

let test_stack_respects_max_retries () =
  Lwt_main.run
    (let () = FakeNet.reset ~ack:false () in
     let cfg =
       {
         Stack.max_retries = 2;
         initial_timeout_s = 0.001;
         max_timeout_s = 0.002;
         timeout_jitter_s = 0.0;
         dedupe_window_s = 1.0;
       }
     in
     let* stack = TestStack.connect ~config:cfg "12000" in
     let* res = TestStack.send stack 8080 "retry" in
     (match res with
     | Ok () -> Alcotest.fail "expected timeout"
     | Error _ -> ());
     Alcotest.(check int) "send attempts" 3 (FakeNet.writes_count ());
     Lwt.return_unit)

let test_stack_success_when_ack_received () =
  Lwt_main.run
    (let () = FakeNet.reset ~ack:true () in
     let cfg =
       {
         Stack.max_retries = 2;
         initial_timeout_s = 0.05;
         max_timeout_s = 0.05;
         timeout_jitter_s = 0.0;
         dedupe_window_s = 1.0;
       }
     in
     let* stack = TestStack.connect ~config:cfg "12001" in
     let* _ = TestStack.listen stack (fun _ _ -> Lwt.return_unit) in
     let* res = TestStack.send stack 8080 "ok" in
     (match res with
     | Ok () -> ()
     | Error e -> Alcotest.failf "expected success, got %a" Net.pp_error e);
     Alcotest.(check int) "single send" 1 (FakeNet.writes_count ());
     Lwt.return_unit)

let () =
  Alcotest.run
    "nano_os"
    [ ( "filesystem+shell",
        [ Alcotest.test_case "create/read file" `Quick test_fs_create_and_read
        ; Alcotest.test_case
            "write_file overwrite"
            `Quick
            test_fs_write_file_overwrites_atomically
        ; Alcotest.test_case "write supports overwrite" `Quick test_shell_write_overwrite
        ; Alcotest.test_case
            "commands are case-insensitive"
            `Quick
            test_shell_case_insensitive_commands
        ; Alcotest.test_case "remove file" `Quick test_shell_rm
        ; Alcotest.test_case
            "repair invalid superblock"
            `Quick
            test_fs_connect_repairs_invalid_superblock
        ] )
    ; ( "packet",
        [ Alcotest.test_case "roundtrip" `Quick test_packet_roundtrip
        ; Alcotest.test_case "checksum validation" `Quick test_packet_checksum_validation
        ] )
    ; ( "stack",
        [ Alcotest.test_case "max retries" `Quick test_stack_respects_max_retries
        ; Alcotest.test_case "ack success" `Quick test_stack_success_when_ack_received
        ] )
    ]
