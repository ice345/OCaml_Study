(* lib/date.mli *)

type date = { month : int; day : int; year : int; }

val is_before : date -> date -> bool

val is_leap_year : int -> bool

val is_valid_date : date -> bool
