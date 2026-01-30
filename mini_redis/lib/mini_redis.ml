(** 
  A minimal implementation of a RESP (REdis Serialization Protocol)
  encoder and decoder in OCaml.

  Supported RESP types:
  - Simple Strings
  - Errors
  - Integers
  - Bulk Strings (including Null Bulk Strings)
  - Arrays (including Null Arrays)

  This module provides:
  - A decoder that consumes a buffer and returns a parsed RESP value
    along with the remaining unconsumed input.
  - An encoder that converts RESP values back into wire format.
*)

(* ========================= *)
(* ===== RESP Datatype ===== *)
(* ========================= *)

(** Representation of RESP data types *)
type resp =
  | SimpleString of string
  | Error of string
  | Integer of int
  | BulkString of string option
      (** [None] represents a Null Bulk String: "$-1\r\n" *)
  | Array of resp list option
      (** [None] represents a Null Array: "*-1\r\n" *)

(* ============================== *)
(* ===== Utility Functions ===== *)
(* ============================== *)

(** 
  Attempt to parse an integer from a string.

  Returns:
  - [Ok int] if parsing succeeds
  - [Error msg] if the string is not a valid integer
*)
let try_parse_int s =
  try Ok (int_of_string s)
  with Failure _ -> Error ("Invalid integer format: ")

(** 
  Find the index of the first CRLF ("\r\n") sequence in a string.

  Returns:
  - [Some idx] where [idx] is the position of '\r'
  - [None] if no valid CRLF sequence is found
*)
let find_crlf str =
  try
    let idx = String.index str '\r' in
    if idx + 1 < String.length str && str.[idx + 1] = '\n' then
      Some idx
    else
      None
  with Not_found -> None

(* ============================ *)
(* ===== RESP Decoder ======== *)
(* ============================ *)

(** 
  Decode a RESP value from the given buffer.

  On success:
  - returns the parsed RESP value
  - returns the remaining unconsumed buffer

  On failure:
  - returns a protocol error message
*)
let rec decode buffer : (resp * string, string) result =
  if String.length buffer = 0 then Error "Empty buffer"
  else
    match buffer.[0] with
    | '+' -> decode_simple_string buffer (fun s -> SimpleString s)
    | '-' -> decode_simple_string buffer (fun s -> Error s)
    | ':' -> decode_int buffer
    | '$' -> decode_bulk_string buffer
    | '*' -> decode_array buffer
    | c -> Error (Printf.sprintf "Invalid RESP type: %c" c)

(** 
  Decode a Simple String or Error.

  Format:
  - Simple String: "+content\r\n"
  - Error:         "-content\r\n"
*)
and decode_simple_string buffer constructor =
  match find_crlf buffer with
  | Some idx ->
      let content = String.sub buffer 1 (idx - 1) in
      let rest = String.sub buffer (idx + 2) (String.length buffer - idx - 2) in
      Ok (constructor content, rest)
  | None -> Error "Incomplete SimpleString/Error"

(** 
  Decode an Integer.

  Format:
  ":number\r\n"
*)
and decode_int buffer =
  match find_crlf buffer with
  | Some idx ->
      let num_str = String.sub buffer 1 (idx - 1) in
      (match try_parse_int num_str with
      | Ok num ->
          let rest = String.sub buffer (idx + 2) (String.length buffer - idx - 2) in
          Ok (Integer num, rest)
      | Error e -> Error e)
  | None -> Error "Incomplete Integer"

(** 
  Decode a Bulk String.

  Formats:
  - Regular bulk string: "$length\r\ncontent\r\n"
  - Null bulk string:    "$-1\r\n"
*)
and decode_bulk_string buffer =
  match find_crlf buffer with
  | None -> Error "Incomplete BulkString length"
  | Some idx ->
      let len_str = String.sub buffer 1 (idx - 1) in
      (match try_parse_int len_str with
      | Error e -> Error e
      | Ok len ->
          if len = -1 then
            let rest = String.sub buffer (idx + 2) (String.length buffer - idx - 2) in
            Ok (BulkString None, rest)
          else
            let content_start = idx + 2 in
            let total_len = content_start + len + 2 in
            if String.length buffer < total_len then
              Error "Incomplete BulkString content"
            else
              let content = String.sub buffer content_start len in
              let rest = String.sub buffer total_len (String.length buffer - total_len) in
              Ok (BulkString (Some content), rest)
      )

(** 
  Decode an Array.

  Formats:
  - Regular array: "*count\r\n[element1][element2]..."
  - Null array:    "*-1\r\n"
*)
and decode_array buffer =
  match find_crlf buffer with
  | None -> Error "Incomplete Array length"
  | Some idx ->
      let len_str = String.sub buffer 1 (idx - 1) in
      match try_parse_int len_str with
      | Error e -> Error e
      | Ok count ->
          if count = -1 then
            let rest = String.sub buffer (idx + 2) (String.length buffer - idx - 2) in
            Ok (Array None, rest)
          else
            let start_rest =
              String.sub buffer (idx + 2) (String.length buffer - idx - 2)
            in
            decode_array_elements count start_rest []

(** 
  Recursively decode [count] RESP elements from the buffer
  to construct an array.
*)
and decode_array_elements count buffer acc =
  if count = 0 then
    Ok (Array (Some (List.rev acc)), buffer)
  else
    match decode buffer with
    | Ok (element, rest) ->
        decode_array_elements (count - 1) rest (element :: acc)
    | Error e -> Error e

(* ============================ *)
(* ===== RESP Encoder ======== *)
(* ============================ *)

(** Encode a RESP value into its wire-format representation *)
let rec encode = function
  | SimpleString s -> "+" ^ s ^ "\r\n"
  | Error s -> "-" ^ s ^ "\r\n"
  | Integer i -> ":" ^ string_of_int i ^ "\r\n"
  | BulkString None -> "$-1\r\n"
  | BulkString (Some s) ->
      "$" ^ string_of_int (String.length s) ^ "\r\n" ^ s ^ "\r\n"
  | Array None -> "*-1\r\n"
  | Array (Some lst) ->
      let len = List.length lst in
      let elems = List.map encode lst |> String.concat "" in
      "*" ^ string_of_int len ^ "\r\n" ^ elems

(* ============================ *)
(* ===== Command Layer ======= *)
(* ============================ *)

(** Supported Redis-like commands *)
type command =
  | Set of string * string
  | Get of string
  | Ping of string option
      (** Optional message payload for PING *)
  | Command_Error of string

(* ============================ *)
(* ===== Key-Value Store ===== *)
(* ============================ *)

(** In-memory key-value store based on a mutable hashtable *)
module Store = struct
  type t = (string, string) Hashtbl.t
  let create () = Hashtbl.create 16
end

(* ============================ *)
(* ===== Command Parsing ===== *)
(* ============================ *)

(** 
  Extract a string value from a RESP value if possible.

  Accepts:
  - BulkString (Some s)
  - SimpleString s
*)
let to_string_opt = function
  | BulkString (Some s) -> Some s
  | SimpleString s -> Some s
  | _ -> None

(** Option monadic bind *)
let ( let* ) = Option.bind

(** Parse a RESP Array into a command *)
let parse_command = function
  | Array (Some (cmd_resp :: args)) ->
      (match to_string_opt cmd_resp with
      | Some cmd_str ->
          (match (String.uppercase_ascii cmd_str, args) with
          | ("PING", []) -> Ping None
          | ("PING", [arg]) ->
              (match to_string_opt arg with
              | Some s -> Ping (Some s)
              | None -> Command_Error "Invalid PING argument")
          | ("GET", [key_resp]) ->
              (match to_string_opt key_resp with
              | Some s -> Get s
              | None -> Command_Error "Invalid key")
          | ("SET", [key_resp; val_resp]) ->
              let result =
                let* k = to_string_opt key_resp in
                let* v = to_string_opt val_resp in
                Some (Set (k, v))
              in
              Option.value result
                ~default:(Command_Error "Invalid key or value")
          | _ ->
              Command_Error ("Unknown command or wrong arguments: " ^ cmd_str))
      | None -> Command_Error "Command must be a string")
  | _ -> Command_Error "Invalid request format"

(* ============================ *)
(* ===== Command Execution === *)
(* ============================ *)

(** Execute a parsed command against the store *)
let execute store cmd =
  match cmd with
  | Ping None -> SimpleString "PONG"
  | Ping (Some msg) -> BulkString (Some msg)
  | Get key ->
      (match Hashtbl.find_opt store key with
      | Some v -> BulkString (Some v)
      | None -> BulkString None)
  | Set (key, value) ->
      Hashtbl.replace store key value;
      SimpleString "OK"
  | Command_Error msg -> Error msg

(* ============================ *)
(* ===== Request Handling ==== *)
(* ============================ *)

(** 
  Decode, parse, execute, and encode a single RESP request.

  Any protocol-level error is returned as a RESP Error.
*)
let handle_request store buffer =
  match decode buffer with
  | Ok (resp, rest) ->
      let cmd = parse_command resp in
      let result = execute store cmd in
      Ok (encode result, rest)
  | Error msg -> Error msg
