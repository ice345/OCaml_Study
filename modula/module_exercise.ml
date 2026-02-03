module type QueueSig = sig
  type 'a t
  val empty : 'a t
  val is_empty : 'a t -> bool
  val enqueue : 'a -> 'a t -> 'a t
  val peek : 'a t -> 'a option
  val dequeue : 'a t -> ('a * 'a t) option
end

module Queue : QueueSig = struct
  type 'a t = 'a list * 'a list

  let norm = function
    | ([], back) -> (List.rev back, [])
    | q -> q

  let empty = ([], [])

  let is_empty (front, back) =
    match front, back with
    | [], [] -> true | _ -> false

  let enqueue x (front, back) =
    norm (front, x :: back)

  let peek (front, _) =
    match front with
    | x :: _ -> Some x
    | [] -> None

  let dequeue (front, back) =
    match front with
    | [] -> None
    | x :: xs -> Some (x, norm (xs, back))
end


module MyList = struct
  include List

  let sum lst =
    fold_left (+) 0 lst
end

module type Ring = sig
  type t
  val zero : t
  val add : t -> t -> t
  val mul : t -> t -> t
  val to_string : t -> string
end

module MakeMath (R : Ring) = struct
  let square x = R.mul x x
end

module IntRing : Ring with type t = int = struct
  type t = int
  let zero = 0
  let add = ( + )
  let mul = ( * )
  let to_string = string_of_int
end

module FloatRing : Ring with type t = float = struct
  type t = float
  let zero = 0.0
  let add = ( +. )
  let mul = ( *. )
  let to_string = string_of_float
end

(* Matrix Functor *)
module MatrixRing (R : Ring) = struct
  type t = R.t array array
  
  (* 这是一个临时的 2x2 zero，为了跑通示例 *)
  let zero = Array.make_matrix 2 2 R.zero

  let add m1 m2 =
    let rows = Array.length m1 in
    let cols = Array.length m1.(0) in
    let res = Array.make_matrix rows cols R.zero in
    for i = 0 to rows - 1 do
      for j = 0 to cols - 1 do
        res.(i).(j) <- R.add m1.(i).(j) m2.(i).(j)
      done
    done;
    res

  let mul m1 m2 =
    let n = Array.length m1 in
    let res = Array.make_matrix n n R.zero in
    for i = 0 to n - 1 do
      for j = 0 to n - 1 do
        let sum = ref R.zero in
        for k = 0 to n - 1 do
          sum := R.add !sum (R.mul m1.(i).(k) m2.(k).(j))
        done;
        res.(i).(j) <- !sum
      done
    done;
    res

  let to_string m = "Matrix..." (* 简化输出 *)
end

(* === 4. 实例化测试 === *)
module IntMath = MakeMath(IntRing)
module MatRingInt = MatrixRing(IntRing)
module MatMath = MakeMath(MatRingInt) (* 矩阵的平方！ *)

let _ = 
  let m = Array.make_matrix 2 2 2 in (* [[2;2]; [2;2]] *)
  let m_sq = MatMath.square m in     (* [[8;8]; [8;8]] *)
  Printf.printf "Matrix squared element: %d\n" m_sq.(0).(0)
