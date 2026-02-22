open Lwt.Syntax

type config = {
  max_retries : int;
  initial_timeout_s : float;
  max_timeout_s : float;
  timeout_jitter_s : float;
  dedupe_window_s : float;
}

let default_config =
  {
    max_retries = 5;
    initial_timeout_s = 0.2;
    max_timeout_s = 2.0;
    timeout_jitter_s = 0.05;
    dedupe_window_s = 30.0;
  }

module type S = sig
  type t
  type net_t
  type clock_t
  type random_t

  val create :
    config:config -> net:net_t -> clock:clock_t -> random:random_t -> my_port:int -> t

  val connect : ?config:config -> string -> t Lwt.t
  val send : t -> int -> string -> (unit, Net.error) result Lwt.t
  val listen : t -> (int -> string -> unit Lwt.t) -> (unit, Net.error) result Lwt.t
end

module Make (N : Net.NETWORK) (C : Clock.S) (R : Nano_random.S) = struct
  type net_t = N.t
  type clock_t = C.t
  type random_t = R.t

  type t = {
    net : N.t;
    clock : C.t;
    random : R.t;
    my_port : int;
    mutable next_seq : int;
    pending_acks : (int, unit Lwt.u) Hashtbl.t;
    seen_data : ((int * int), int64) Hashtbl.t;
    config : config;
  }

  let clamp_timeout cfg timeout_s =
    let t = min cfg.max_timeout_s timeout_s in
    max 0.0 t

  let timeout_for_attempt t attempt =
    let base = t.config.initial_timeout_s *. (2. ** float_of_int attempt) in
    let jitter =
      if t.config.timeout_jitter_s <= 0.0 then 0.0
      else R.float t.random t.config.timeout_jitter_s
    in
    clamp_timeout t.config (base +. jitter)

  let create ~config ~net ~clock ~random ~my_port =
    let next_seq = R.int random 256 in
    {
      net;
      clock;
      random;
      my_port;
      next_seq;
      pending_acks = Hashtbl.create 16;
      seen_data = Hashtbl.create 256;
      config;
    }

  let connect ?(config = default_config) port_str =
    let* net = N.connect port_str in
    let* clock = C.connect () in
    let* random = R.connect () in
    let my_port = int_of_string port_str in
    Lwt.return (create ~config ~net ~clock ~random ~my_port)

  let dedupe_window_ns t = Int64.of_float (t.config.dedupe_window_s *. 1_000_000_000.0)

  let prune_seen t now_ns =
    let window = dedupe_window_ns t in
    if window <= 0L then Hashtbl.clear t.seen_data
    else
      let stale_keys = ref [] in
      Hashtbl.iter
        (fun key seen_at ->
          if Int64.sub now_ns seen_at > window then stale_keys := key :: !stale_keys)
        t.seen_data;
      List.iter (Hashtbl.remove t.seen_data) !stale_keys

  let send t dst_port msg_str =
    let seq = t.next_seq in
    t.next_seq <- (seq + 1) mod 256;

    let packet = Packet.encode_data ~seq ~src_port:t.my_port ~payload:msg_str in
    let dst = string_of_int dst_port in

    Hashtbl.remove t.pending_acks seq;
    let waiter, awakener = Lwt.wait () in
    Hashtbl.add t.pending_acks seq awakener;

    let cleanup_pending () = Hashtbl.remove t.pending_acks seq in

    let rec send_until_ack attempt =
      let* write_res = N.write t.net ~dst packet in
      match write_res with
      | Error _ as err ->
          cleanup_pending ();
          Lwt.return err
      | Ok () ->
          let timeout_s = timeout_for_attempt t attempt in
          let timeout =
            let* () = C.sleep_s t.clock timeout_s in
            Lwt.return `Timeout
          in
          let acked =
            let* () = waiter in
            Lwt.return `Acked
          in
          let* result = Lwt.pick [ timeout; acked ] in
          (match result with
          | `Acked ->
              cleanup_pending ();
              Lwt.return (Ok ())
          | `Timeout ->
              if attempt >= t.config.max_retries then (
                cleanup_pending ();
                Lwt.return
                  (Error
                     (`Unknown
                       (Printf.sprintf
                          "ACK timeout for seq=%d after %d attempts"
                          seq
                          (attempt + 1)))))
              else send_until_ack (attempt + 1))
    in
    send_until_ack 0

  let listen t callback =
    N.listen t.net (fun raw_packet ->
        match Packet.decode raw_packet with
        | Error _ -> Lwt.return_unit
        | Ok packet ->
            (match packet.kind with
            | Packet.Ack ->
                let ack_seq = packet.ack in
                (match Hashtbl.find_opt t.pending_acks ack_seq with
                | Some wakener ->
                    Hashtbl.remove t.pending_acks ack_seq;
                    Lwt.wakeup_later wakener ();
                    Lwt.return_unit
                | None -> Lwt.return_unit)
            | Packet.Data ->
                let ack_buf = Packet.encode_ack ~ack:packet.seq ~src_port:t.my_port in
                Lwt.async (fun () ->
                    let* _ = N.write t.net ~dst:(string_of_int packet.src_port) ack_buf in
                    Lwt.return_unit);
                let now_ns = C.now_ns t.clock in
                prune_seen t now_ns;
                let dedupe_key = (packet.src_port, packet.seq) in
                (match Hashtbl.find_opt t.seen_data dedupe_key with
                | Some seen_at when Int64.sub now_ns seen_at <= dedupe_window_ns t ->
                    Lwt.return_unit
                | _ ->
                    Hashtbl.replace t.seen_data dedupe_key now_ns;
                    callback packet.src_port packet.payload)))
end
