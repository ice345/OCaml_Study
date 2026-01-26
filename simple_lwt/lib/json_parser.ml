(* Definition *)

(* Example: { "a": 1, "b": true } *)
type json = 
  | Null
  | Bool of bool
  | Int of int
  | Float of float
  | String of string
  | Array of json list
  | Object of (string * json) list

(* Example token structure:
[
  LBrace;
  Str "a"; Colon; Num 1; Comma;
  Str "b"; Colon; Bool true;
  RBrace
]
*)
type token = 
  | LBrace  (*{*)
  | RBrace  (*}*)
  | LBracket  (*[*)
  | RBracket  (*]*)
  | Colon  (*:*)
  | Comma  (*,*)
  | Str of string
  | IntTok of int
  | FloatTok of float
  | Bool of bool
  | Null

(* Token processing *)

let string_to_list s = List.init (String.length s) (String.get s)

let is_digit_or_dot c = 
  '0' <= c && c <= '9' || c = '.' || c = '-' || c = 'e' || c = 'E'

let rec lex_number acc chars =
  match chars with
  | c :: rest when is_digit_or_dot c ->
      (* If the char is digit, add it to the acc then continue *)
      lex_number (c :: acc) rest
  | _ -> 
      (* 1. If the char is not digit then stop *)
      let num_str = String.of_seq (List.to_seq (List.rev acc)) in
      let token = 
        try IntTok (int_of_string num_str)
        with Failure _ -> FloatTok (float_of_string num_str)
      in
      (* 2. Return token and the rest chars *)
      (token, chars)

(* 处理最后的引号用的 *)
let rec lex_string acc chars =
  match chars with
  | '"' :: rest ->
      (* 遇到闭合的引号,结束 *)
      let s = String.of_seq (List.to_seq (List.rev acc)) in
      (Str s, rest)
  | c :: rest ->
      (* 普通字符 *)
      lex_string (c :: acc) rest
  | [] -> failwith "Unclosed string" (* 字符串没有闭合就结束了 *)

let rec lex chars =
  match chars with
  | [] -> []
  | ' ' :: rest | '\n' :: rest | '\r' :: rest | '\t' :: rest -> lex rest
  | '{' :: rest -> LBrace :: lex rest
  | '}' :: rest -> RBrace :: lex rest
  | '[' :: rest -> LBracket :: lex rest
  | ']' :: rest -> RBracket :: lex rest
  | ':' :: rest -> Colon :: lex rest
  | ',' :: rest -> Comma :: lex rest
  | '"' :: rest -> 
      let (token, remaining) = lex_string [] rest in
      token :: lex remaining
  | 't' :: 'r' :: 'u' :: 'e' :: rest -> Bool true :: lex rest
  | 'f' :: 'a' :: 'l' :: 's' :: 'e' :: rest -> Bool false :: lex rest
  | 'n' :: 'u' :: 'l' :: 'l' :: rest -> Null :: lex rest
  | c :: rest when is_digit_or_dot c ->
      let (token, remaining) = lex_number [] (c :: rest) in
      token :: lex remaining
  | _ -> failwith "Unknown character"


(* AST construction *)
let rec parse_value tokens =
  match tokens with
  | IntTok n :: rest -> (Int n, rest)
  | FloatTok f :: rest -> (Float f, rest)
  | Bool b :: rest -> (Bool b, rest)
  | Str s :: rest -> (String s, rest)
  | Null :: rest -> (Null, rest)
  (* 如果遇到 { 或 [, 说明是复杂结构, 需要递归调用 *)
  | LBrace :: rest -> parse_object rest
  | LBracket :: rest -> parse_array rest
  | _ -> failwith "Unexpected token"

and parse_array tokens =
  (* 此时 tokens 已经去掉了开头的 [ *)
  match tokens with
  | RBracket :: rest -> (Array [], rest) (* 空数组 [] *)
  | _ ->
      let (vals, rest) = parse_comma_separated_value [] tokens in
      (Array vals, rest)

(* 通用的列表解析器: 解析 p, p, p... 直到遇到 end_token *)
and parse_comma_separated_value acc tokens =
  match tokens with
  | RBracket :: rest -> (List.rev acc, rest) (* 遇到 ] 结束 *)
  | _ ->
      (* 1. 解析一个值 *)
      let (v, rest1) = parse_value tokens in
      (* 2. 看后面是不是逗号 *)
      match rest1 with
      | Comma :: rest2 -> parse_comma_separated_value (v :: acc) rest2 (* 有逗号,继续 *)
      | RBracket :: rest2 -> (List.rev (v :: acc), rest2)
      | _ -> failwith "Expected comma or closing bracket"

and parse_object tokens =
  (* 此时 tokens 已经去掉了开头的 { *)
  match tokens with
  | RBrace :: rest -> (Object [], rest) (* 空对象 {} *)
  | _ -> 
      let (fields, rest) = parse_object_fields [] tokens in
      (Object fields, rest)

and parse_object_fields acc tokens =
  match tokens with
  | Str k :: rest1 ->
      (match rest1 with
      | Colon :: rest2 -> 
          let (v, rest3) = parse_value rest2 in
          (match rest3 with
          | Comma :: rest4 ->
              parse_object_fields ((k, v) :: acc) rest4
          | RBrace :: rest4 ->
              (List.rev ((k, v) :: acc), rest4)
          | _ ->
              failwith "Expected comma or closing brace")
      | _ -> 
          failwith "Expected colon")
  | _ -> 
      failwith "Expected string key"

let parse_json str =
  let tokens = lex (string_to_list str) in
  let (json, rest) = parse_value tokens in
  match rest with
  | [] -> json  (* 必须正好把 TOKEN 吃完 *)
  | _ -> failwith "Extra data after JSON"

(* 查找对象中的key *)
let member key json =
  match json with
  | Object fields ->
      List.assoc_opt key fields
  | _ -> None

(* 查找数组中的索引 *)
let index i json =
  match json with
  | Array elems ->
      if i < 0 then None
      else List.nth_opt elems i
  | _ -> None

let (>>=) = Option.bind

(* 定义对象访问符 |. *)
(* 逻辑是:如果左边是 Some json, 就调用 member key; 如果是 None, 就继续传递 None *)
let (|.) json_opt key =
  json_opt >>= member key

(* 定义数组访问符 |@ *)
(* 逻辑是:如果左边是 Some json, 就调用 index i; 如果是 None, 就继续传递 None *)
let (|@) json_opt i =
  json_opt >>= index i

let rec to_string (json : json) =
  match json with
  | Null -> "null"
  | Bool b -> string_of_bool b
  | Int n -> string_of_int n
  | Float f -> string_of_float f
  | String s -> "\"" ^ s ^ "\""
  | Array elems ->
      let elems_str = List.map to_string elems in
      "[" ^ String.concat ", " elems_str ^ "]"
  | Object fields ->
      let field_strs = 
        List.map (fun (k, v) -> "\"" ^ k ^ "\": " ^ to_string v) fields 
      in
      "{" ^ String.concat ", " field_strs ^ "}"
