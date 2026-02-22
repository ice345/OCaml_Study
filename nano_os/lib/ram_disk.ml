type write_error = Block.error
type read_error = Block.error

type t = {
  data : Cstruct.t;
  info : Block.info;
}

let sector_size = 512


let connect _name = 
  let size_bytes = 1024 * 1024 in
  let data = Cstruct.create size_bytes in
  let size_sectors = Int64.of_int (size_bytes / sector_size) in
  let info = {
    Block.size_sectors = size_sectors;
    Block.sector_size = sector_size;
    Block.read_write = true;
  } in
  Lwt.return { data; info }

let disconnect _t = Lwt.return_unit

let get_info t = Lwt.return t.info

let check_bounds t sector_start len_bytes = 
  let offset = Int64.mul sector_start (Int64.of_int t.info.Block.sector_size) in
  let total_len = Int64.add offset (Int64.of_int len_bytes) in
  if total_len > (Int64.of_int (Cstruct.length t.data)) then
    Error (`Out_of_bounds sector_start)
  else
    Ok (Int64.to_int offset)

let read t sector_start buffers = 
  let total_len = Cstruct.lenv buffers in
  match check_bounds t sector_start total_len with
  | Error e -> Lwt.return (Error e)
  | Ok offset ->
      let src = Cstruct.sub t.data offset total_len in
      let rec copy_loop src = function
        | [] -> ()
        | dst :: rest ->
            let len = Cstruct.length dst in
            let curr_src = Cstruct.sub src 0 len in
            let next_src = Cstruct.sub src len (Cstruct.length src - len) in
            Cstruct.blit curr_src 0 dst 0 len;
            copy_loop next_src rest
      in
      copy_loop src buffers;
      Lwt.return (Ok ())

let write t sector_start buffers = 
  let total_len = Cstruct.lenv buffers in
  match check_bounds t sector_start total_len with
  | Error e -> Lwt.return (Error e)
  | Ok offset ->
      let dst = Cstruct.sub t.data offset total_len in
      let rec copy_loop dst = function
        | [] -> ()
        | src :: rest ->
            let len = Cstruct.length src in
            let curr_dst = Cstruct.sub dst 0 len in
            let next_dst = Cstruct.sub dst len (Cstruct.length dst - len) in
            Cstruct.blit src 0 curr_dst 0 len;
            copy_loop next_dst rest
      in
      copy_loop dst buffers;
      Lwt.return (Ok ())
