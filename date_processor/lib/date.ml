(* lib/date.ml *)

type date = {
  month : int;
  day : int;
  year : int;
}

(** [is_before d1 d2] 判斷 [d1] 是否在 [d2] 之前。
    Requires: [d1] 和 [d2] 是有效的日期（雖然此處暫不檢查月份合法性）。
    Returns: 如果 [d1] 早於 [d2] 則為 true，否則為 false。 *)
let is_before d1 d2 =
  if d1.year < d2.year then true
  else if d1.year > d2.year then false
  else if d1.month < d2.month then true
  else if d1.month > d2.month then false
  else d1.day < d2.day

(** [is_leap_year year] 判斷 [year] 是否為閏年。
    Returns: 如果 [year] 是閏年則為 true，否則為 false。 *)
let is_leap_year year =
  (year mod 4 = 0 && year mod 100 <> 0) || (year mod 400 = 0)

(** [is_valid_date d] 判斷 [d] 是否為有效的日期。
    Returns: 如果 [d] 是有效日期則為 true，否則為 false。 *)
let is_valid_date d =
  let days_in_month month year =
    match month with
    | 1 | 3 | 5 | 7 | 8 | 10 | 12 -> 31
    | 4 | 6 | 9 | 11 -> 30
    | 2 -> if is_leap_year year then 29 else 28
    | _ -> 0
  in
  d.month >= 1 && d.month <= 12 &&
  d.day >= 1 && d.day <= days_in_month d.month d.year
