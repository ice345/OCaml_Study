open Json_parser

(* --- 测试辅助工具 --- *)

(* 定义 json 类型的 testable，用于 Alcotest 的比较和打印 *)
let json_t = Alcotest.testable (fun ppf t -> Fmt.pf ppf "%s" (to_string t)) (=)

(* 定义一个辅助函数来测试 "Round Trip" 性质 *)
(* 原理：parse(str) -> to_string -> parse -> should be same structure *)
(* 注意：字符串可能有空格差异，所以我们比较的是 AST 结构，而不是字符串本身 *)
let test_round_trip name input_str =
  let json1 = parse_json input_str in
  let str2 = to_string json1 in
  let json2 = parse_json str2 in
  Alcotest.(check json_t) (name ^ " (Round Trip)") json1 json2

(* --- 1. Parser Tests (Deserialization) --- *)

let test_parse_atoms () =
  Alcotest.(check json_t) "null" Null (parse_json "null");
  Alcotest.(check json_t) "true" (Bool true) (parse_json "true");
  Alcotest.(check json_t) "false" (Bool false) (parse_json "false");
  Alcotest.(check json_t) "int" (Int 42) (parse_json "42");
  Alcotest.(check json_t) "float" (Float 3.14) (parse_json "3.14");
  Alcotest.(check json_t) "string" (String "hello") (parse_json "\"hello\"")

let test_parse_complex () =
  let input = "[1, {\"a\": true}, [null], [3, 3.4]]" in
  let expected = Array [
    Int 1;
    Object [("a", Bool true)];
    Array [Null];
    Array [Int 3; Float 3.4]
  ] in
  Alcotest.(check json_t) "complex structure" expected (parse_json input)

let test_parse_error () =
  (* 测试非法输入是否抛出异常 *)
  (* Alcotest.check_raises 需要期望的异常类型 *)
  (* 这里我们假设你的 parse 代码抛出的是 Failure _ *)
  try 
    let _ = parse_json "{ invalid }" in
    Alcotest.fail "Should have raised exception"
  with Failure _ -> () 
  | _ -> Alcotest.fail "Raised wrong exception type"

let test_parse_error_2 () =
  (* 测试用例 1: 词法错误 *)
  (* 输入一个非法字符 @，期望抛出 Failure "Unknown character" *)
  Alcotest.check_raises
    "Lexer error on unknown char"
    (Failure "Unknown character")
    (fun () -> ignore (parse_json "{ @ }"));

  (* 测试用例 2: 语法错误 *)
  (* 输入 { 123 }，key 不是字符串，期望抛出 Failure "Expected string key" *)
  Alcotest.check_raises
    "Parser error on invalid key"
    (Failure "Expected string key")
    (fun () -> ignore (parse_json "{ 123: 1 }"))

(* --- 2. Printer Tests (Serialization) --- *)

let test_to_string () =
  (* 检查基本的格式化输出 *)
  let json = Object [("k", Int 1)] in
  (* 注意：你的 to_string 实现可能会有空格差异，这里假设是紧凑或简单带空格的格式 *)
  (* 如果你的实现是 "{\"k\": 1}" *)
  let output = to_string json in
  (* 简单的包含检查，或者精确匹配 *)
  if not (String.contains output 'k') then Alcotest.fail "Output missing key"

let test_round_trips () =
  (* 这是一个非常强大的测试策略：往返测试 *)
  test_round_trip "Simple Object" "{\"x\": 100}";
  test_round_trip "Nested Array" "[1, [2, 3], 4]";

  (* 复杂的集成测试 *)
  let complex_json = {|
    {
      "id": 12345,
      "name": "Example Project",
      "active": true,
      "rating": 3.4,
      "tags": ["json", "test", "round-trip", "complex"],
      "owner": {
        "username": "ice345",
        "email": "user@example.com",
        "roles": ["admin", "developer"],
        "profile": {
          "age": 22,
          "location": {
            "country": "Singapore",
            "city": "Singapore",
            "coordinates": [103.0, 1.3]
          }
        }
      },
      "settings": {
        "theme": "dark",
        "notifications": {
          "email": true,
          "sms": false,
          "push": null
        },
        "limits": {
          "storage_mb": 10240,
          "projects": 50
        }
      },
      "history": [
        {
          "timestamp": "2025-01-01T10:00:00Z",
          "action": "create"
        },
        {
          "timestamp": "2025-01-02T12:30:00Z",
          "action": "update",
          "changes": ["name", "settings.theme"]
        }
      ]
    }
  |} in
  test_round_trip "Complex Integration" complex_json

(* --- 3. Accessor Tests (Query) --- *)

let test_accessors () =
  let data = parse_json "{\"users\": [{\"name\": \"Alice\", \"age\": 34}, {\"name\": \"Bob\", \"age\": 20}]}" in
  
  (* 测试成功的路径 *)
  let res_name = Some data |. "users" |@ 0 |. "name" in
  Alcotest.(check (option json_t)) "extract Alice" (Some (String "Alice")) res_name;

  let res_age = Some data |. "users" |@ 1 |. "age" in
  Alcotest.(check (option json_t)) "extract Bob's age" (Some (Int 20)) res_age;

  (* 测试失败路径：Key 不存在 *)
  let res_fail = Some data |. "404" in
  Alcotest.(check (option json_t)) "missing key" None res_fail;

  (* 测试失败路径：类型错误 (对 Object 用 Index) *)
  let res_type_err = Some data |@ 0 in
  Alcotest.(check (option json_t)) "type error" None res_type_err

(* --- 注册所有测试 --- *)

let () =
  let open Alcotest in
  run "Simple_json_tests" [
    ("Parser", [
      test_case "Atoms" `Quick test_parse_atoms;
      test_case "Complex" `Quick test_parse_complex;
      test_case "Errors" `Quick test_parse_error;
      test_case "Errors 2" `Quick test_parse_error_2;
    ]);
    ("Serialization", [
      test_case "To String" `Quick test_to_string;
      test_case "Round Trip" `Quick test_round_trips;
    ]);
    ("Query", [
      test_case "Accessors" `Quick test_accessors;
    ]);
  ]
