open Json_parser

let () =
  let json_str = "{\"project\": \"dune\", \"status\": \"awesome\"}" in
  print_endline ("Parsing: " ^ json_str);
  
  let json = parse_json json_str in
  
  (* 尝试提取数据 *)
  match Some json |. "project" with
  | Some (String s) -> print_endline ("Project name: " ^ s)
  | _ -> print_endline "Error: key not found"
