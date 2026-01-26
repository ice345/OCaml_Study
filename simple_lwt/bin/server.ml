open Lwt.Syntax
open Cohttp_lwt_unix
open Json_parser

let store = Hashtbl.create 16

(* ============================= *)
(* 1. 处理 HTTP 请求的逻辑       *)
(* ============================= *)

let callback _conn req body =
  let uri = Request.uri req in
  let path = Uri.path uri in
  let meth = Request.meth req in

  match (meth, path) with
  (* 1. GET /get?key=xyz *)
  | (`GET, "/get") ->
      let key_opt = Uri.get_query_param uri "key" in
      (match key_opt with
       | Some key ->
           (match Hashtbl.find_opt store key with
            | Some value ->
                let json = Object [("value", String value)] in
                Server.respond_string ~status:`OK ~body:(to_string json) ()
            | None ->
                Server.respond_string ~status:`Not_found ~body:"Key not found" ())
       | None ->
           Server.respond_string ~status:`Bad_request ~body:"Missing key param" ())

  (* 2. POST /set *)
  | (`POST, "/set") ->
      (* 用 Lwt.catch 包整个异步处理，保证异常不会炸掉连接 *)
      Lwt.catch
        (fun () ->
           let* body_str = Cohttp_lwt.Body.to_string body in
           (* parse_json 可能抛异常 *)
           let json =
             try parse_json body_str
             with Failure msg -> failwith ("JSON parse error: " ^ msg)
           in
           (* 提取 key/value *)
           match (Some json |. "key", Some json |. "value") with
           | (Some (String k), Some (String v)) ->
               Hashtbl.replace store k v;
               Server.respond_string ~status:`OK ~body:"Saved" ()
           | _ ->
               Server.respond_string ~status:`Bad_request ~body:"Invalid JSON format" ()
        )
        (function
          | Failure msg ->
              Server.respond_string ~status:`Bad_request ~body:msg ()
          | exn ->
              Server.respond_string ~status:`Internal_server_error
                ~body:("Unexpected error: " ^ Printexc.to_string exn) ()
        )

  (* 3. 404 *)
  | _ ->
      Server.respond_string ~status:`Not_found ~body:"Route not found" ()

(* ============================= *)
(* 2. 启动服务器                  *)
(* ============================= *)
let start_server port =
  let server = Server.make ~callback () in
  let mode = `TCP (`Port port) in
  Printf.printf "Starting server on port %d...\n%!" port;
  Server.create ~mode server

let () =
  let port = 8080 in
  Lwt_main.run (start_server port)
