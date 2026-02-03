type _ key =
  | KeyInt : string -> int key
  | KeyString : string -> string key
  | KeyBool : string -> bool key

type entry =
  | Entry : 'a key * 'a -> entry

type (_, _) eq =
  | Refl : ('a, 'a) eq


type t = entry list

let empty = []

let eq_key : type a b. a key -> b key -> (a, b) eq option =
  fun k1 k2 ->
    match (k1, k2) with
    | KeyInt n1, KeyInt n2 when n1 = n2 -> Some Refl
    | KeyString n1, KeyString n2 when n1 = n2 -> Some Refl
    | KeyBool n1, KeyBool n2 when n1 = n2 -> Some Refl
    | _ -> None

let put : type a. a key -> a -> t -> t =
  fun k v store ->
    Entry (k, v) :: store

let rec get : type a. a key -> t -> a option =
  fun k store ->
    match store with
    | [] -> None
    | Entry (k', v) :: rest ->
        match eq_key k k' with
        | Some Refl -> Some v
        | None -> get k rest

let port_key = KeyInt "port"
let host_key = KeyString "host"
let debug_key = KeyBool "debug"

let s = empty
        |> put port_key 8080
        |> put host_key "127.0.0.1"
        |> put debug_key true


