open Lwt.Syntax

module type S = sig
  type t

  val eval : t -> string -> string Lwt.t
end

module Make (FS : Fs.S) = struct
  type t = FS.t

  let help_msg =
    "Available commands:\n"
    ^ "  ls                  - List files\n"
    ^ "  cat <file>          - Read file content\n"
    ^ "  write <file> <msg>  - Create or overwrite file\n"
    ^ "  touch <file>        - Create empty file\n"
    ^ "  rm <file>           - Delete file\n"
    ^ "  help                - Show this help"

  let eval fs cmd_str =
    let parts = String.split_on_char ' ' cmd_str |> List.filter (fun s -> s <> "") in
    match parts with
    | [] -> Lwt.return ""
    | command :: args ->
        let command = String.lowercase_ascii command in
        (match (command, args) with
        | "ls", [] ->
            let* files = FS.ls fs in
            if files = [] then Lwt.return "Directory is empty."
            else Lwt.return (String.concat "\n" files)
        | "cat", [ filename ] ->
            let* res = FS.read_file fs filename in
            (match res with
            | Ok content -> Lwt.return content
            | Error (`File_not_found _) -> Lwt.return ("Error: File not found: " ^ filename)
            | Error _ -> Lwt.return "Error: Read failed")
        | "write", filename :: words ->
            let content = String.concat " " words in
            let* files = FS.ls fs in
            let existed_before = List.mem filename files in
            let* res = FS.write_file fs filename content in
            (match res with
            | Ok () when existed_before -> Lwt.return "File overwritten successfully."
            | Ok () -> Lwt.return "File created successfully."
            | Error `No_space -> Lwt.return "Error: Disk full."
            | Error _ -> Lwt.return "Error: Write failed.")
        | "touch", [ filename ] ->
            let* res = FS.create_file fs filename "" in
            (match res with
            | Ok () -> Lwt.return "File created."
            | Error (`File_exists _) ->
                Lwt.return ("Error: File " ^ filename ^ " already exists.")
            | Error _ -> Lwt.return "Error: Touch failed")
        | "rm", [ filename ] ->
            let* res = FS.delete_file fs filename in
            (match res with
            | Ok () -> Lwt.return "File deleted."
            | Error (`File_not_found _) -> Lwt.return ("Error: File not found: " ^ filename)
            | Error _ -> Lwt.return "Error: Delete failed")
        | "help", [] -> Lwt.return help_msg
        | _ -> Lwt.return ("Unknown command: " ^ cmd_str ^ "\nType 'help' for usage."))
end
