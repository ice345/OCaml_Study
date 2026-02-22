(* lib/file_disk.ml *)
open Lwt.Syntax
open Nano_os

type error = Block.error
type write_error = Block.error
type read_error = Block.error
type info = Block.info

type t = {
  fd : Lwt_unix.file_descr;
  info : Block.info;
}

(* File-backed block device; initializes to 1MB if empty. *)
let get_info t = Lwt.return t.info

let disconnect t = Lwt_unix.close t.fd

let connect name =
  let flags = [Unix.O_RDWR; Unix.O_CREAT] in
  let perm = 0o644 in
  let* fd = Lwt_unix.openfile name flags perm in
  
  let* stats = Lwt_unix.fstat fd in
  let* size_bytes = 
    if stats.st_size = 0 then (
      (* 初始化 1MB 大小 *)
      let* () = Lwt_unix.ftruncate fd (1024 * 1024) in
      Lwt.return (1024 * 1024)
    ) else Lwt.return stats.st_size 
  in
  
  let sector_size = 512 in
  let size_sectors = Int64.of_int (size_bytes / sector_size) in
  
  let info = {
    Block.size_sectors = size_sectors;
    Block.sector_size = sector_size;
    Block.read_write = true;
  } in
  
  Lwt.return { fd; info }

let read t sector_start buffers =
  let offset = Int64.mul sector_start (Int64.of_int t.info.Block.sector_size) in
  
  (* Lwt_unix.lseek 不支持 64 位 offset 在 32位系统上，但这里假定 64 位环境或者文件较小 *)
  (* 注意：Unix.lseek takes int. 这是一个潜在限制，但在 demo 够用 *)
  let* _ = Lwt_unix.lseek t.fd (Int64.to_int offset) Unix.SEEK_SET in
  
  let rec read_loop = function
    | [] -> Lwt.return (Ok ())
    | buf :: rest ->
        let len = Cstruct.length buf in
        let bytes = Bytes.create len in
        let* n = Lwt_unix.read t.fd bytes 0 len in
        if n < len then Lwt.return (Error (`Out_of_bounds sector_start)) (* 简单处理 EOF *)
        else
          let () = Cstruct.blit_from_bytes bytes 0 buf 0 len in
          read_loop rest
  in
  read_loop buffers

let write t sector_start buffers =
  let offset = Int64.mul sector_start (Int64.of_int t.info.Block.sector_size) in
  let* _ = Lwt_unix.lseek t.fd (Int64.to_int offset) Unix.SEEK_SET in
  
  let rec write_loop = function
    | [] -> Lwt.return (Ok ())
    | buf :: rest ->
        let len = Cstruct.length buf in
        let bytes = Cstruct.to_bytes buf in
        let* n = Lwt_unix.write t.fd bytes 0 len in
        if n < len then Lwt.return (Error (`Out_of_bounds sector_start))
        else write_loop rest
  in
  write_loop buffers
