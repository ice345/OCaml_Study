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
      let rec extract_string acc chars =
        match chars with
        | '"' :: rest -> (String.concat "" (List.rev acc), rest)
        | c :: rest -> extract_string (String.make 1 c :: acc) rest
        | [] -> failwith "Unterminated string"
      in
      let (str, remaining) = extract_string [] rest in
      Str str :: lex remaining
  | 't' :: 'r' :: 'u' :: 'e' :: rest -> Bool true :: lex rest
  | 'f' :: 'a' :: 'l' :: 's' :: 'e' :: rest -> Bool false :: lex rest
  | 'n' :: 'u' :: 'l' :: 'l' :: rest -> Null :: lex rest
  | c :: rest when Char.code c >= Char.code '0' && Char.code c <= Char.code '9' ->
      let rec extract_number acc chars =
        match chars with
        | d :: rest when Char.code d >= Char.code '0' && Char.code d <= Char.code '9' ->
            extract_number (acc ^ String.make 1 d) rest
        | _ -> (int_of_string acc, chars)
      in
      let (num, remaining) = extract_number (String.make 1 c) rest in
      Num num :: lex remaining
  | _ -> failwith "Unknown character"
