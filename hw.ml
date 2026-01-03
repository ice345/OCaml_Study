(*Promble 1*)
let encode_pro lst =
  let rec loop lst todo =
    match lst with
    | [] -> List.rev todo
    | head :: tail ->
        let new_todo =
          match todo with
          | (k, v) :: rest when k = head -> (k, v + 1) :: rest
          | _ -> (head, 1) :: todo
        in
        loop tail new_todo
  in
  loop lst []

let encode lst =
  let rec loop lst todo =
    match lst with
    | [] -> List.rev todo
    | head :: tail ->
        let new_todo =
          match todo with
          | (k, v) :: rest ->
              if k = head then
                (k, v + 1) :: rest
              else
                (head, 1) :: todo
          | _ -> (head, 1) :: todo
        in
        loop tail new_todo
  in
  loop lst []

(*Promble 2*)
type expr =
  | Const of int
  | Add of expr * expr
  | Div of expr * expr

let ( let* ) = Option.bind

let rec eval e =
  match e with
  | Const n -> Some n
  | Add (e1, e2) -> (
    let* v1 = eval e1 in
    let* v2 = eval e2 in
    Some (v1 + v2)
  )
  | Div (e1, e2) -> (
    let* v1 = eval e1 in
    let* v2 = eval e2 in
    if v2 = 0 then None else Some (v1 / v2)
  )

(*Promble 3*)
let process_data (lst : int list) =
  List.filter (fun x -> x mod 2 = 0) lst
  |> List.map (fun x -> x * x)
  |> List.fold_left (fun acc x -> acc + x) 0

let process_data_pro (lst : int list) = lst
  |> List.filter (fun x -> x mod 2 = 0)
  |> List.map (fun x -> x * x)
  |> List.fold_left (fun acc x -> acc + x) 0

