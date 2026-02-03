type _ expr =
  | I : int -> int expr
  | B : bool -> bool expr
  | Add : int expr * int expr -> int expr
  | Eq : 'a expr * 'a expr -> bool expr
  | If : bool expr * 'a expr * 'a expr -> 'a expr


(* eval : type a. a expr -> a *)
(* 这句话的意思是：对于任何类型 a，如果你给我一个 a expr，我就一定还给你一个原生的 a *)
let rec eval : type a. a expr -> a = function
  | I n -> n
  | B b -> b
  | Add (e1, e2) -> eval e1 + eval e2
  | Eq (e1, e2) -> eval e1 = eval e2
  | If (cond, e1, e2) ->
      if eval cond then eval e1 else eval e2


type zero = Zero
type 'n succ = Succ of 'n

type (_, _) vec =
  | Nil : ('a, zero) vec
  | Cons : 'a * ('a, 'n) vec -> ('a, 'n succ) vec

(* 类型 ('n, 'm, 's) plus 代表证明：n + m = s *)
type (_, _, _) plus =
  (* 规则 1: 0 + m = m *)
  | Plus_Z : (zero, 'm, 'm) plus
  
  (* 规则 2: (n + 1) + m = (s + 1)
     前提是你得先证明 n + m = s *)
  | Plus_S : ('n, 'm, 's) plus -> ('n succ, 'm, 's succ) plus

let safe_head : type a n. (a, n succ) vec -> a = function
  | Cons (x, _) -> x

(* 参数说明：
   proof: 证明 n + m = s
   v1   : 长度为 n 的向量
   v2   : 长度为 m 的向量
   返回  : 长度为 s 的向量
*)
let rec append : type n m s a. (n, m, s) plus -> (a, n) vec -> (a, m) vec -> (a, s) vec =
  fun proof v1 v2 ->
  match proof, v1 with
  (* Case 1: n 是 0。根据加法规则，结果长度应该是 m。
     同时 v1 是空向量 (Nil)。
     直接返回 v2 (它的长度就是 m)，类型完美匹配！ *)
  | Plus_Z, Nil -> v2

  (* Case 2: n 是 n' succ。根据规则，结果长度应该是 s' succ。
     proof 里面剥离出一个子证明 p (证明 n' + m = s')。
     v1 剥离出头部 x 和尾部 xs (长度 n')。
     递归调用 append，得到长度为 s' 的尾部，再把 x 接上去。*)
  | Plus_S p, Cons (x, xs) -> Cons (x, append p xs v2)

  (* 编译器知道其他情况是不可能的，比如 Plus_Z (n=0) 碰上 Cons (n>0) 
     所以这里不需要写其他分支 *)

(* 定义一些测试数据 *)
let v1 = Cons(1, Cons(2, Nil)) (* 长度 2 *)
let v2 = Cons(3, Nil)          (* 长度 1 *)

(* 我们想做 v1 + v2。
   长度应该是 2 + 1 = 3。
   我们需要构造一个证明：Plus_S (Plus_S Plus_Z) 
   这代表 2 + m = (m+2) 
*)

(* 构造证明：2 + 1 = 3 *)
(* 逻辑链：
   Plus_Z           证明 0 + 1 = 1
   Plus_S Plus_Z    证明 1 + 1 = 2
   Plus_S ...       证明 2 + 1 = 3
*)
let p2 = Plus_S (Plus_S (Plus_Z))

(* 调用 *)
let v3 = append p2 v1 v2
(* v3 的类型是 (int, zero succ succ succ) vec，即长度为 3 *)
