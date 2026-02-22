open Lwt.Syntax

type error =
  [ `Block_error of Block.error
  | `File_not_found of string
  | `File_exists of string
  | `No_space
  | `Corrupt_filesystem
  ]

let pp_error ppf = function
  | `Block_error e -> Block.pp_error ppf e
  | `File_not_found s -> Fmt.pf ppf "File not found: %s" s
  | `File_exists s -> Fmt.pf ppf "File exists: %s" s
  | `No_space -> Fmt.string ppf "No space left on device"
  | `Corrupt_filesystem -> Fmt.string ppf "Corrupt filesystem"

module type S = sig
  type t
  type block_t

  val format : t -> (unit, error) result Lwt.t
  val create_file : t -> string -> string -> (unit, error) result Lwt.t
  val write_file : t -> string -> string -> (unit, error) result Lwt.t
  val read_file : t -> string -> (string, error) result Lwt.t
  val ls : t -> string list Lwt.t
  val delete_file : t -> string -> (unit, error) result Lwt.t

  val connect : ?repair:bool -> block_t -> t Lwt.t
  val is_formatted : t -> bool Lwt.t
end

module Make (B : Block.BLOCK) : S with type block_t = B.t = struct
  type entry = {
    name : string;
    start : int32;
    size : int32;
  }

  type t = {
    disk : B.t;
    info : Block.info;
    cache : (string, int32 * int32) Hashtbl.t;
  }

  type block_t = B.t

  let magic_str = "NANO_FS\000"
  let header_size = 16
  let entry_size = 64
  let max_files = 32
  let directory_bytes = header_size + (max_files * entry_size)
  let directory_sectors = (directory_bytes + 511) / 512

  let sectors_for_size size =
    if size <= 0 then 0 else (size + 511) / 512

  let parse_name raw_name =
    match String.index_opt raw_name '\000' with
    | Some i -> String.sub raw_name 0 i
    | None -> raw_name

  let read_superblock fs =
    let buf = Cstruct.create (directory_sectors * 512) in
    let* read_res = B.read fs.disk 0L [ buf ] in
    match read_res with
    | Ok () -> Lwt.return (Ok buf)
    | Error e -> Lwt.return (Error (`Block_error e))

  let update_cache fs entries =
    Hashtbl.clear fs.cache;
    List.iter (fun entry -> Hashtbl.replace fs.cache entry.name (entry.start, entry.size)) entries

  let write_superblock fs entries next_free =
    let buf = Cstruct.create (directory_sectors * 512) in
    Cstruct.blit_from_string magic_str 0 buf 0 8;
    Cstruct.LE.set_uint32 buf 8 (Int32.of_int (List.length entries));
    Cstruct.LE.set_uint32 buf 12 next_free;
    List.iteri
      (fun i entry ->
        let offset = header_size + (i * entry_size) in
        let limited_name =
          if String.length entry.name > 56 then String.sub entry.name 0 56 else entry.name
        in
        let name_buf = Cstruct.create 56 in
        Cstruct.blit_from_string limited_name 0 name_buf 0 (String.length limited_name);
        Cstruct.blit name_buf 0 buf offset 56;
        Cstruct.LE.set_uint32 buf (offset + 56) entry.start;
        Cstruct.LE.set_uint32 buf (offset + 60) entry.size)
      entries;
    let* write_res = B.write fs.disk 0L [ buf ] in
    match write_res with
    | Ok () ->
        update_cache fs entries;
        Lwt.return (Ok ())
    | Error e -> Lwt.return (Error (`Block_error e))

  let validate_entry fs entry =
    let disk_sectors = Int64.to_int fs.info.Block.size_sectors in
    let start = Int32.to_int entry.start in
    let size = Int32.to_int entry.size in
    let sectors_needed = sectors_for_size size in
    let finish = start + sectors_needed in
    let name_ok = entry.name <> "" in
    let start_ok = start >= directory_sectors && start <= disk_sectors in
    let size_ok = size >= 0 in
    let finish_ok = finish <= disk_sectors in
    name_ok && start_ok && size_ok && finish_ok

  let parse_superblock fs buf =
    let magic = Cstruct.to_string (Cstruct.sub buf 0 8) in
    if magic <> magic_str then Error `Corrupt_filesystem
    else
      let raw_count = Int32.to_int (Cstruct.LE.get_uint32 buf 8) in
      let raw_next_free = Cstruct.LE.get_uint32 buf 12 in
      let dirty = ref false in
      if raw_count > max_files then dirty := true;
      let count = min raw_count max_files in
      let dedupe = Hashtbl.create count in
      let entries_rev = ref [] in
      for i = 0 to count - 1 do
        let offset = header_size + (i * entry_size) in
        let name = parse_name (Cstruct.to_string (Cstruct.sub buf offset 56)) in
        let start = Cstruct.LE.get_uint32 buf (offset + 56) in
        let size = Cstruct.LE.get_uint32 buf (offset + 60) in
        let entry = { name; start; size } in
        if validate_entry fs entry then
          if Hashtbl.mem dedupe name then dirty := true
          else (
            Hashtbl.add dedupe name ();
            entries_rev := entry :: !entries_rev)
        else dirty := true
      done;
      let entries = List.rev !entries_rev in
      let computed_next_free =
        List.fold_left
          (fun acc entry ->
            let sectors_needed = sectors_for_size (Int32.to_int entry.size) in
            max acc (Int32.add entry.start (Int32.of_int sectors_needed)))
          (Int32.of_int directory_sectors)
          entries
      in
      let repaired_next_free =
        let min_next = max (Int32.of_int directory_sectors) computed_next_free in
        let disk_limit = Int32.of_int (Int64.to_int fs.info.Block.size_sectors) in
        if min_next > disk_limit then disk_limit else min_next
      in
      if raw_next_free <> repaired_next_free then dirty := true;
      Ok (entries, repaired_next_free, !dirty)

  let is_formatted fs =
    let* super_res = read_superblock fs in
    match super_res with
    | Error _ -> Lwt.return false
    | Ok buf ->
        let magic = Cstruct.to_string (Cstruct.sub buf 0 8) in
        Lwt.return (magic = magic_str)

  let connect ?(repair = true) disk =
    let* info = B.get_info disk in
    let fs = { disk; info; cache = Hashtbl.create 16 } in
    let* super_res = read_superblock fs in
    match super_res with
    | Error _ -> Lwt.return fs
    | Ok buf ->
        let magic = Cstruct.to_string (Cstruct.sub buf 0 8) in
        if magic <> magic_str then Lwt.return fs
        else (
          match parse_superblock fs buf with
          | Error _ -> Lwt.return fs
          | Ok (entries, next_free, dirty) ->
              update_cache fs entries;
              if repair && dirty then
                let* _ = write_superblock fs entries next_free in
                Lwt.return fs
              else Lwt.return fs)

  let format fs = write_superblock fs [] (Int32.of_int directory_sectors)

  let ls fs =
    let files = Hashtbl.fold (fun name _ acc -> name :: acc) fs.cache [] in
    Lwt.return files

  let load_entries fs =
    let* super_res = read_superblock fs in
    match super_res with
    | Error e -> Lwt.return (Error e)
    | Ok buf ->
        (match parse_superblock fs buf with
        | Error e -> Lwt.return (Error e)
        | Ok parsed -> Lwt.return (Ok parsed))

  let write_file fs filename content =
    let content_len = String.length content in
    let sectors_needed = sectors_for_size content_len in
    let* loaded = load_entries fs in
    match loaded with
    | Error e -> Lwt.return (Error e)
    | Ok (entries, next_free, _) ->
        let existing = List.exists (fun entry -> entry.name = filename) entries in
        if (not existing) && List.length entries >= max_files then Lwt.return (Error `No_space)
        else
          let next_free_i = Int32.to_int next_free in
          let disk_sectors = Int64.to_int fs.info.Block.size_sectors in
          if next_free_i + sectors_needed > disk_sectors then Lwt.return (Error `No_space)
          else
            let data_buf = Cstruct.create (sectors_needed * 512) in
            Cstruct.blit_from_string content 0 data_buf 0 content_len;
            let* data_res = B.write fs.disk (Int64.of_int32 next_free) [ data_buf ] in
            match data_res with
            | Error e -> Lwt.return (Error (`Block_error e))
            | Ok () ->
                let new_entry = { name = filename; start = next_free; size = Int32.of_int content_len } in
                let entries' =
                  if existing then
                    List.map
                      (fun entry -> if entry.name = filename then new_entry else entry)
                      entries
                  else entries @ [ new_entry ]
                in
                let next_free' = Int32.add next_free (Int32.of_int sectors_needed) in
                write_superblock fs entries' next_free'

  let create_file fs filename content =
    if Hashtbl.mem fs.cache filename then Lwt.return (Error (`File_exists filename))
    else write_file fs filename content

  let read_file fs filename =
    match Hashtbl.find_opt fs.cache filename with
    | None -> Lwt.return (Error (`File_not_found filename))
    | Some (start, size) ->
        let size_i = Int32.to_int size in
        let sectors_needed = sectors_for_size size_i in
        let data_buf = Cstruct.create (sectors_needed * 512) in
        let* read_res = B.read fs.disk (Int64.of_int32 start) [ data_buf ] in
        match read_res with
        | Error e -> Lwt.return (Error (`Block_error e))
        | Ok () ->
            let content = Cstruct.to_string (Cstruct.sub data_buf 0 size_i) in
            Lwt.return (Ok content)

  let delete_file fs filename =
    let* loaded = load_entries fs in
    match loaded with
    | Error e -> Lwt.return (Error e)
    | Ok (entries, next_free, _) ->
        let kept = List.filter (fun entry -> entry.name <> filename) entries in
        if List.length kept = List.length entries then Lwt.return (Error (`File_not_found filename))
        else write_superblock fs kept next_free
end
