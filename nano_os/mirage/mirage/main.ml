open Lwt.Infix
type 'a io = 'a Lwt.t
let return = Lwt.return
let run t = Solo5_os.Main.run t ; exit
0

let mirage_runtime_delay__key = Mirage_runtime.register_arg @@
# 32 "lib/devices/runtime_arg.ml"
  Mirage_runtime.delay
;;

let mirage_runtime_logs__key = Mirage_runtime.register_arg @@
# 199 "lib/devices/runtime_arg.ml"
  Mirage_runtime.logs
;;

let cmdliner_stdlib_setup_backtracesome_true_randomize_hashtablessome_true___key = Mirage_runtime.register_arg @@
# 380 "lib/mirage.ml"
  Cmdliner_stdlib.setup ~backtrace:(Some true) ~randomize_hashtables:(Some true) ()
;;

# 23 "mirage/main.ml"

module Unikernel_main__13 = Unikernel.Main(Block)(Netif)(Mirage_mtime)

let mirage_bootvar__1 = lazy (
# 15 "lib/devices/argv.ml"
  return (Mirage_bootvar.argv ())
);;
# 31 "mirage/main.ml"

let struct_end__2 = lazy (
  let __mirage_bootvar__1 = Lazy.force mirage_bootvar__1 in
  __mirage_bootvar__1 >>= fun _mirage_bootvar__1 ->
# 47 "lib/functoria/job.ml"
  return Mirage_runtime.(with_argv (runtime_args ()) "nano_os" _mirage_bootvar__1)
);;
# 39 "mirage/main.ml"

let cmdliner_stdlib__3 = lazy (
  let _cmdliner_stdlib_setup_backtracesome_true_randomize_hashtablessome_true_ = (cmdliner_stdlib_setup_backtracesome_true_randomize_hashtablessome_true___key ()) in
  return (_cmdliner_stdlib_setup_backtracesome_true_randomize_hashtablessome_true_)
);;
# 45 "mirage/main.ml"

let mirage_runtime__4 = lazy (
  let _mirage_runtime_delay = (mirage_runtime_delay__key ()) in
# 266 "lib/mirage.ml"
  Mirage_sleep.ns (Duration.of_sec _mirage_runtime_delay)
);;
# 52 "mirage/main.ml"

let mirage_logs__5 = lazy (
  let _mirage_runtime_logs = (mirage_runtime_logs__key ()) in
# 20 "lib/devices/reporter.ml"
  let reporter = Mirage_logs.create () in
  Mirage_runtime.set_level ~default:(Some Logs.Info) _mirage_runtime_logs;
  Logs.set_reporter reporter;
  Lwt.return reporter
);;
# 62 "mirage/main.ml"

let mirage_sleep__6 = lazy (
  return ()
);;
# 67 "mirage/main.ml"

let mirage_ptime__7 = lazy (
  return ()
);;
# 72 "mirage/main.ml"

let mirage_mtime__8 = lazy (
  return ()
);;
# 77 "mirage/main.ml"

let mirage_crypto_rng_mirage__9 = lazy (
# 13 "lib/devices/random.ml"
  Mirage_crypto_rng_mirage.initialize (module Mirage_crypto_rng.Fortuna)
);;
# 83 "mirage/main.ml"

let mirage_runtime__10 = lazy (
# 275 "lib/mirage.ml"
  Mirage_runtime.set_name "nano_os"; Lwt.return_unit
);;
# 89 "mirage/main.ml"

let block__11 = lazy (
# 88 "lib/devices/block.ml"
  Block.connect "nanodisk"
);;
# 95 "mirage/main.ml"

let netif__12 = lazy (
# 25 "lib/devices/network.ml"
  Netif.connect "service"
);;
# 101 "mirage/main.ml"

let unikernel_main__13 = lazy (
  let __block__11 = Lazy.force block__11 in
  let __netif__12 = Lazy.force netif__12 in
  let __mirage_mtime__8 = Lazy.force mirage_mtime__8 in
  __block__11 >>= fun _block__11 ->
  __netif__12 >>= fun _netif__12 ->
  __mirage_mtime__8 >>= fun _mirage_mtime__8 ->
  (Unikernel_main__13.start _block__11 _netif__12 _mirage_mtime__8 : unit io)
);;
# 112 "mirage/main.ml"

let mirage_runtime__14 = lazy (
  let __struct_end__2 = Lazy.force struct_end__2 in
  let __cmdliner_stdlib__3 = Lazy.force cmdliner_stdlib__3 in
  let __mirage_runtime__4 = Lazy.force mirage_runtime__4 in
  let __mirage_logs__5 = Lazy.force mirage_logs__5 in
  let __mirage_sleep__6 = Lazy.force mirage_sleep__6 in
  let __mirage_ptime__7 = Lazy.force mirage_ptime__7 in
  let __mirage_mtime__8 = Lazy.force mirage_mtime__8 in
  let __mirage_crypto_rng_mirage__9 = Lazy.force mirage_crypto_rng_mirage__9 in
  let __mirage_runtime__10 = Lazy.force mirage_runtime__10 in
  let __unikernel_main__13 = Lazy.force unikernel_main__13 in
  __struct_end__2 >>= fun _struct_end__2 ->
  __cmdliner_stdlib__3 >>= fun _cmdliner_stdlib__3 ->
  __mirage_runtime__4 >>= fun _mirage_runtime__4 ->
  __mirage_logs__5 >>= fun _mirage_logs__5 ->
  __mirage_sleep__6 >>= fun _mirage_sleep__6 ->
  __mirage_ptime__7 >>= fun _mirage_ptime__7 ->
  __mirage_mtime__8 >>= fun _mirage_mtime__8 ->
  __mirage_crypto_rng_mirage__9 >>= fun _mirage_crypto_rng_mirage__9 ->
  __mirage_runtime__10 >>= fun _mirage_runtime__10 ->
  __unikernel_main__13 >>= fun _unikernel_main__13 ->
# 361 "lib/mirage.ml"
  return ()
);;
# 138 "mirage/main.ml"

let () =
  let t = Lazy.force struct_end__2 >>= fun _ ->
  Lazy.force cmdliner_stdlib__3 >>= fun _ ->
  Lazy.force mirage_runtime__4 >>= fun _ ->
  Lazy.force mirage_logs__5 >>= fun _ ->
  Lazy.force mirage_sleep__6 >>= fun _ ->
  Lazy.force mirage_ptime__7 >>= fun _ ->
  Lazy.force mirage_mtime__8 >>= fun _ ->
  Lazy.force mirage_crypto_rng_mirage__9 >>= fun _ ->
  Lazy.force mirage_runtime__10 >>= fun _ ->
  Lazy.force mirage_runtime__14 in
  run t
;;
