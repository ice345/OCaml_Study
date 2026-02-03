module type DateSig = sig
  type t
  val make : int -> int -> int -> t option
  val to_string : t -> string
end

module Date : DateSig = struct
  type t = int

  let is_valid y m d =
    if m < 1 || m > 12 || d < 1 || d > 31 then false
    else if m = 2 && d > 29 then false
    else true

  let make y m d =
    if is_valid y m d then
      Some (y * 10000 + m * 100 + d)
    else
      None

  let to_string t =
    let y = t / 10000 in
    let m = (t mod 10000) / 100 in
    let d = t mod 100 in
    Printf.sprintf "%04d-%02d-%02d" y m d
end


module type OrderedType = sig
  type t
  val compare : t -> t -> int
end

module MakeMap (Key : OrderedType) : sig
  type 'v t
  val empty : 'v t
  val add : Key.t -> 'v -> 'v t -> 'v t
  val find : Key.t -> 'v t -> 'v option
end = struct
  type 'v t = (Key.t * 'v) list

  let empty = []

  let add key value store =
    (key, value) :: List.filter (fun (k, _) -> Key.compare k key <> 0) store

  let rec find key store =
    match store with
    | [] -> None
    | (k, v) :: rest ->
        if Key.compare k key = 0 then Some v
        else find key rest
end

module StringKey = struct
  type t = string
  let compare = String.compare
end

module StringMap = MakeMap(StringKey)


module IntKey = struct
  type t = int
  let compare = Int.compare
end

module IntMap = MakeMap(IntKey)
