open Lwt.Syntax

module type CLOCK = sig
  val now : unit -> string
end

module type CONSOLE = sig
  val log : string -> unit Lwt.t
end

module type KV_STORE = sig
  type t

  val create : unit -> t
  val set : t -> string -> string -> unit Lwt.t
  val get : t -> string -> string option Lwt.t
end

module MakeKV (C : CLOCK) (L : CONSOLE) : KV_STORE = struct
  type t = (string, string) Hashtbl.t

  let create () : t = Hashtbl.create 16

  (* 核心逻辑: 设置Key-Value *)
  (* 1. 获取 C.now() 的时间 *)
  (* 2. 拼装日志消息 *)
  (* 3. 调用 L.log 打印日志 *)
  (* 4. 更新 Hashtbl *)
  let set (kv : t) (key : string) (value : string) : unit Lwt.t =
    let timestamp = C.now () in
    let log_msg = "[" ^ timestamp ^ "] SET " ^ key ^ " = " ^ value in
    let* () = L.log log_msg in
    Hashtbl.replace kv key value;
    Lwt.return_unit

  (* 获取Key对应的Value *)
  let get (kv : t) (key : string) : string option Lwt.t =
    Lwt.return (Hashtbl.find_opt kv key)
end
