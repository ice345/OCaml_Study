open Nano_os
open Lwt.Syntax

type error = Net.error

type t = {
  sock : Lwt_unix.file_descr;
  addr : Lwt_unix.sockaddr;
}

(* UDP socket backend. NANO_IP can override the destination IP. *)
let connect port_str =
  let port = int_of_string port_str in
  let sock = Lwt_unix.socket Lwt_unix.PF_INET Lwt_unix.SOCK_DGRAM 0 in
  let addr = Lwt_unix.ADDR_INET (Unix.inet_addr_any, port) in
  let* () = Lwt_unix.bind sock addr in
  Lwt.return { sock; addr }

let disconnect t =
  let* () = Lwt_unix.close t.sock in
  Lwt.return_unit

let write t ~dst buffer =
  let bytes = Cstruct.to_bytes buffer in
  try
    let port = int_of_string dst in
    let target_ip = try Sys.getenv "NANO_IP" with Not_found -> "127.0.0.1" in
    let dst_addr = Lwt_unix.ADDR_INET (Unix.inet_addr_of_string target_ip, port) in
    let* _ = Lwt_unix.sendto t.sock bytes 0 (Bytes.length bytes) [] dst_addr in
    Lwt.return (Ok ())
  with exn -> Lwt.return (Error (`Unknown (Printexc.to_string exn)))

let listen t callback =
  let buffer = Bytes.create 4096 in
  let rec loop () =
    let* (len, _sender) = Lwt_unix.recvfrom t.sock buffer 0 4096 [] in
    let packet = Cstruct.of_string (Bytes.sub_string buffer 0 len) in
    Lwt.async (fun () -> callback packet);
    loop ()
  in
  Lwt.catch
    (fun () -> loop ())
    (fun exn -> Lwt.return (Error (`Unknown (Printexc.to_string exn))))
