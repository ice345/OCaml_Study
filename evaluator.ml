type expr =
  | Value of int
  | Var of string
  | Add of expr * expr
  | Let of string * expr * expr

let rec safe_assoc key env =
  match env with
  | [] -> None
  | (k, v) :: tail ->
      if k = key then Some v
      else safe_assoc key tail

let opt_add v1_opt v2_opt =
  match v1_opt, v2_opt with
  | Some v1, Some v2 -> Some (v1 + v2)
  | _ -> None

let rec eval env (e : expr) =
  match e with
  | Value n -> Some n
  | Var s -> safe_assoc s env
  | Add (e1, e2) -> 
      (* (match eval env e1, eval env e2 with *)
      (*   | Some v1, Some v2 -> Some (v1 + v2) *)
      (*   | _ -> None) *)
      let v1_opt = eval env e1 in
      let v2_opt = eval env e2 in
      opt_add v1_opt v2_opt
  | Let (x, e1, e2) -> 
      match eval env e1 with
      | None -> None
      | Some v1 ->
          let new_env = (x, v1) :: env in
          eval new_env e2


