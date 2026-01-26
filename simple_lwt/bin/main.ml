open Lwt.Syntax
(* 使用 let* 语法糖 *)

(* ============================= *)
(* 1. 单个客户端的处理逻辑      *)
(* ============================= *)

let rec handle_loop ic oc =
  (* 读取一行 *)
  let* line = Lwt_io.read_line ic in
  (* 回显 *)
  let* () = Lwt_io.write_line oc ("Echo: " ^ line) in
  (* 递归处理下一行 *)
  handle_loop ic oc

let handle_client (ic, oc) =
  (* 捕获所有异常，确保无论发生什么，Lwt 线程都能正常结束 *)
  Lwt.catch
    (fun () -> handle_loop ic oc)
    (function
      | End_of_file ->
          (* 客户端正常断开（例如按了 Ctrl+D 或关闭了 nc） *)
          Lwt_io.printl "Client disconnected."
      | exn ->
          (* 其他网络异常 *)
          Lwt_io.printl ("Error: " ^ Printexc.to_string exn)
    )

(* ============================= *)
(* 2. 服务器启动逻辑            *)
(* ============================= *)

let start_server () =
  let listen_address = Unix.ADDR_INET (Unix.inet_addr_any, 9000) in

  let* _server =
    Lwt_io.establish_server_with_client_address
      listen_address
      (fun _client_addr (ic, oc) ->
         (* 修正点：直接返回 handle_client 的 Promise。
            establish_server 会等待这个 Promise 完成后，才自动关闭连接。
            
            注意：establish_server 内部已经并发处理了每个连接，
            所以这里不需要（也不能）使用 Lwt.async，否则会导致连接过早关闭。 *)
         handle_client (ic, oc)
      )
  in

  let* () = Lwt_io.printl "Server started on port 9000..." in
  
  (* 创建一个永远挂起的 Promise，防止主程序退出 *)
  fst (Lwt.wait ())

(* ============================= *)
(* 3. 程序入口                  *)
(* ============================= *)

let () =
  (* 捕获可能从最外层逃逸的异步异常 *)
  Lwt_main.run (
    Lwt.catch
      (fun () -> start_server ())
      (fun exn -> Lwt_io.printl ("Fatal error: " ^ Printexc.to_string exn))
  )
