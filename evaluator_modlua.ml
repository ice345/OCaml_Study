module type ENV = sig
  type 'a t
  val empty : 'a t
  val add : string -> 'a -> 'a t -> 'a t
  val lookup : string -> 'a t -> 'a option
  val merge : 'a t -> 'a t -> 'a t
end

module ListEnv : ENV = struct
  type 'a t = (string * 'a) list
  let empty = []
  let add k v env = (k, v) :: env
  let lookup k env = List.assoc_opt k env
  let merge env1 env2 = env1 @ env2
end

module MakeEvaluator (E : ENV) = struct
  type expr =
    | Value of int
    | Var of string
    | Add of expr * expr
    | Let of string * expr * expr

  let (>>=) = Option.bind

  let rec eval env = function
    | Value n -> Some n
    | Var s -> E.lookup s env
    | Add (e1, e2) ->
        eval env e1 >>= fun v1 ->
        eval env e2 >>= fun v2 ->
        Some (v1 + v2)
    | Let (x, e1, e2) ->
        eval env e1 >>= fun v1 ->
        eval (E.add x v1 env) e2
end


(* type expr = *)
(*   | Value of int *)
(*   | Var of string *)
(*   | Add of expr * expr *)
(*   | Let of string * expr * expr *)
(**)
(* let opt_add v1_opt v2_opt = *)
(*   match v1_opt, v2_opt with *)
(*   | Some v1, Some v2 -> Some (v1 + v2) *)
(*   | _ -> None *)
(**)
(**)
(* let ( let* ) = Option.bind *)
(**)
(* let rec eval env = function *)
(*   | Value n -> Some n *)
(*   | Var s -> ListEnv.lookup s env *)
(*   | Add (e1, e2) -> *)
(*       let* v1 = eval env e1 in *)
(*       let* v2 = eval env e2 in *)
(*       Some (v1 + v2) *)
(*   | Let (x, e1, e2) -> *)
(*       let* v1 = eval env e1 in *)
(*       let new_env = ListEnv.add x v1 env in *)
(*       eval new_env e2 *)
