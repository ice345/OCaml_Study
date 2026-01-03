open OUnit2
open Date_processor.Date (* 這裡路徑取決於你的項目名和文件名 *)

(* 輔助函數：快速創建日期 *)
let make_date m d y = { month = m; day = d; year = y }

let test_leap_year _ =
  assert_bool "2000 應該是閏年" (is_leap_year 2000);
  assert_bool "1900 不應該是閏年" (not (is_leap_year 1900));
  assert_bool "2024 應該是閏年" (is_leap_year 2024);
  assert_bool "2023 不應該是閏年" (not (is_leap_year 2023))

let test_valid_date _ =
  assert_bool "2/29/2024 應該是有效日期" (is_valid_date (make_date 2 29 2024));
  assert_bool "2/29/2023 不應該是有效日期" (not (is_valid_date (make_date 2 29 2023)));
  assert_bool "4/31/2024 不應該是有效日期" (not (is_valid_date (make_date 4 31 2024)));
  assert_bool "12/31/2024 應該是有效日期" (is_valid_date (make_date 12 31 2024));
  assert_bool "0/10/2024 不應該是有效日期" (not (is_valid_date (make_date 0 10 2024)));
  assert_bool "13/10/2024 不應該是有效日期" (not (is_valid_date (make_date 13 10 2024)))

let tests =
  "test_suite_for_date" >::: [
    "test_leap_year" >:: test_leap_year;
    "test_valid_date" >:: test_valid_date;
    "year_before" >:: (fun _ -> 
      assert_bool "2023 應該在 2024 之前" (is_before (make_date 1 1 2023) (make_date 1 1 2024)));
    
    "same_year_month_before" >:: (fun _ ->
      assert_bool "1月應該在2月之前" (is_before (make_date 1 10 2024) (make_date 2 1 2024)));
    
    "same_month_day_before" >:: (fun _ ->
      assert_bool "1號應該在2號之前" (is_before (make_date 10 1 2024) (make_date 10 2 2024)));
    
    "equal_dates" >:: (fun _ ->
      assert_bool "相同日期不應判定為 before" (not (is_before (make_date 1 1 2024) (make_date 1 1 2024))));
      
    "year_after" >:: (fun _ ->
      assert_bool "2025 不應在 2024 之前" (not (is_before (make_date 1 1 2025) (make_date 1 1 2024))));
  ]

let _ = run_test_tt_main tests
