open Lwt.Syntax
open Mini_redis

let store = Store.create ()

let rec handle_loop ic oc accum_buffer =
  (* 1. 先尝试处理累积的 buffer *)
  match Mini_redis.handle_request store accum_buffer with
  | Ok (response, rest) ->
      (* A. 成功解析出一个命令 *)
      (* 写回响应 *)
      let* () = Lwt_io.write oc response in
      let* () = Lwt_io.flush oc in
      
      (* B. 关键：立即递归！*)
      (* 因为 rest 里可能还包含第二个、第三个命令（粘包）*)
      (* 我们不需要读新网络数据，直接处理剩下的 *)
      handle_loop ic oc rest

  | Error "Empty buffer" ->
      (* buffer 空了，或者处理完了，去读新数据 *)
      read_more ic oc accum_buffer

  | Error msg when String.sub msg 0 10 = "Incomplete" ->
      (* 数据不够，去读新数据拼接到 accum_buffer 后面 *)
      read_more ic oc accum_buffer

  | Error msg ->
      (* 真正的协议错误 *)
      Lwt_io.printl ("Protocol Error: " ^ msg)
      (* 可以选择断开连接，或者清空 buffer *)

(* 辅助：读更多数据 *)
and read_more ic oc old_buffer =
  let temp_buf = Bytes.create 1024 in
  let* len = Lwt_io.read_into ic temp_buf 0 1024 in
  if len = 0 then
    Lwt_io.printl "Client disconnected"
  else
    let new_data = Bytes.sub_string temp_buf 0 len in
    (* 拼接旧数据和新数据，继续循环 *)
    handle_loop ic oc (old_buffer ^ new_data)

let accept_connection _conn (ic, oc) =
  Lwt.catch
    (fun () -> handle_loop ic oc "")
    (fun _ -> Lwt.return_unit)

let start_server port =
  let addr = Unix.ADDR_INET (Unix.inet_addr_any, port) in
  let* _ = Lwt_io.establish_server_with_client_address addr accept_connection in
  let* () = Lwt_io.printlf "Redis server started on port %d" port in
  fst (Lwt.wait ())

let () =
  Lwt_main.run (start_server 6379)
