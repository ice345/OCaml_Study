type response =
  | Pending
  | Success of string
  | Failure of int

let res =
  [1; 2; 3; 4]
  |> List.filter (fun x -> x mod 2 = 0)
  |> List.map (fun x -> x * 2)
  |> List.fold_left (fun acc x -> acc + x) 0

type fs_node =
  | File of string * int
  | Dir of string * fs_node list

let rec total_size = function
  | File (_, size) -> size
  | Dir (_, children) ->
      List.fold_left (fun acc child -> acc + total_size child) 0 children

let max_in_list = function
  | [] -> None
  | x :: t -> let final_max =
      List.fold_left (fun base other -> if other > base then other else base) x t
  in Some(final_max)


let safe_div mol den =
  if den = 0 then None else Some (mol / den)

let safe_sqrt n = (* 注意：sqrt 只需要接收除法的结果 *)
  if n < 0 then None else Some (int_of_float (sqrt (float_of_int n)))

let ( let* ) = Option.bind

let calc a b =
  let* div_res = safe_div a b in (* 第一步：除法 *)
  let* sqrt_res = safe_sqrt div_res in (* 第二步：直接用除法的结果求平方根 *)
  Some sqrt_res (* 最后包装成 Some *)

let count_true bool_list =
  (* List.fold_left (fun acc b -> if b then acc + 1 else acc) 0 bool_list *)
  List.fold_left (fun acc b -> acc + Bool.to_int b) 0 bool_list

type item =
  | Profit of int
  | Loss of int
  | Comment of string

let calculate_net (lst : item list) =
  List.fold_left (fun acc i -> match i with
  | Profit n -> acc + n
  | Loss n -> acc - n
  | Comment _ -> acc) 0 lst

type 'a tree =
  | Leaf
  | Node of 'a * 'a tree * 'a tree

let rec size t =
  match t with
  | Leaf -> 0
  | Node (_, lt, rt) -> 1 + size lt + size rt

let size_tail t =
  let rec loop acc todo =
    match todo with
    | [] -> acc
    | head :: rest ->
        match head with
        | Leaf -> loop acc rest
        | Node (_, lt, rt) -> loop (acc + 1) rest
  in
  loop 0 [t]

(*你发现上面的match head这里其实可以省略*)

let size_tail t =
  let rec loop acc todo =
    match todo with
    | [] -> acc
    | Leaf :: rest -> loop acc rest
    | Node (_, lt, rt) :: rest -> loop (acc + 1) rest
  in
  loop 0 [t]

let rec map_tree (f : 'a -> 'b) (t : 'a tree) : ('b tree)=
  match t with
  | Leaf -> Leaf
  | Node (v, lt, rt) -> Node (f v, map_tree f lt, map_tree f rt)

