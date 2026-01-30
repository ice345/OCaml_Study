open Alcotest
open Mini_redis

(* 辅助：定义 Result 的测试比较器 *)
(* 因为 handle_request 返回 (string * string, string) result *)
let result_t = result (pair string string) string

(* 测试 1: 正常处理单个完整命令 *)
let test_handle_simple () =
  let store = Store.create () in
  let req = "*1\r\n$4\r\nPING\r\n" in
  let expected = Ok ("+PONG\r\n", "") in (* 剩余字符串应为空 *)
  check result_t "ping" expected (handle_request store req)

(* 测试 2: 粘包 (Sticky Packet) *)
(* 输入包含两个命令：PING 和 ECHO hello *)
(* 期望：处理 PING，返回 PONG，并把剩下的 ECHO hello 完整返回 *)
let test_sticky_packet () =
  let store = Store.create () in
  let cmd1 = "*1\r\n$4\r\nPING\r\n" in
  let cmd2 = "*2\r\n$4\r\nECHO\r\n$5\r\nhello\r\n" in (* 假设你实现了 ECHO，或者用 SET *)
  let input = cmd1 ^ cmd2 in
  
  match handle_request store input with
  | Ok (resp, rest) ->
      check string "response is pong" "+PONG\r\n" resp;
      check string "rest is cmd2" cmd2 rest
  | Error e -> fail ("Unexpected error: " ^ e)

(* 测试 3: 拆包 (Partial Packet) *)
(* 输入只有半个命令 *)
let test_partial_packet () =
  let store = Store.create () in
  let input = "*3\r\n$3\r\nSE" in (* SET 命令没写完 *)
  
  match handle_request store input with
  | Error msg -> 
      (* 检查错误消息是否包含 "Incomplete" 关键字 *)
      let is_incomplete = String.length msg >= 10 && String.sub msg 0 10 = "Incomplete" in
      check bool "error is incomplete" true is_incomplete
  | Ok _ -> fail "Should not parse incomplete packet"

(* 注册测试 *)
let () =
  run "Mini_redis_tests" [
    ("Engine", [
      test_case "Simple" `Quick test_handle_simple;
      test_case "Sticky" `Quick test_sticky_packet;
      test_case "Partial" `Quick test_partial_packet;
    ]);
  ]
