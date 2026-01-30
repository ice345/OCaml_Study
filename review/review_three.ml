let safe_exec f =
  try
    let res = f () in
    Ok res
  with
  | exn ->
      let msg = Printexc.to_string exn in
      Error msg
