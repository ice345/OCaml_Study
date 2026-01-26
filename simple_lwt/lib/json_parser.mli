(** Json Parser library for OCaml *)

(** Json data type *)
type json =
  | Null
  | Bool of bool
  | Int of int
  | Float of float
  | String of string
  | Array of json list
  | Object of (string * json) list

(** {1. Serialization & Deserialization} *)

(** Parse a string into a JSON AST.
    @raise Failure if the string is not valid JSON. *)
val parse_json : string -> json

(** Convert a JSON AST back to a string representation *)
val to_string : json -> string

(** {2. Accessors & Querying} *)

(** Look up an index in a JSON Object *)
val member : string -> json -> json option

(** Look up an index in a JSON Array. *)
val index : int -> json -> json option

(** {3. Infix Operators} *)

(** Object field accessor: [json_opt |. "key"] *)
val (|.) : json option -> string -> json option

(** Array index accessor: [json_opt |@ index] *)
val (|@) : json option -> int -> json option
