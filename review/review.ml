type op =
  | Add of int
  | Sub of int
  | Mul of int
  | Div of int
  | Reset

let rec calculate acc ops =
  match ops with
  | [] -> acc
  | op :: rest ->
      let new_acc =
        match op with
        | Add n -> acc + n
        | Sub n -> acc - n
        | Mul n -> acc * n
        | Div n -> if n <> 0 then acc / n else acc
        | Reset -> 0
      in
      calculate new_acc rest

(* Example usage *)
let () =
  let operations = [Add 5; Mul 2; Sub 3; Div 4; Reset; Add 10] in
  let result = calculate 0 operations in
  Printf.printf "Final result: %d\n" result
