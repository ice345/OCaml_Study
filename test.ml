type account = {
  deposit : int -> unit;
  withdraw : int -> bool;
  get_balance : unit -> int;
}

let make_account initial_balance =
  let balance = ref initial_balance in
  {
    deposit = (fun amount -> 
      if amount < 0 then 
        invalid_arg "deposit: negative amount"
      else
        balance := !balance + amount
    );
    withdraw = (fun amount -> 
      if amount < 0 then
        invalid_arg "withdraw: negative amount"
      else if amount > !balance then
        false
      else (
        balance := !balance - amount;
        true
      )
    );
    get_balance = (fun () -> !balance);
  }
