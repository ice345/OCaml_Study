open Lwt.Syntax

module Main
    (Blk : Mirage_block.S)
    (Netif : Mirage_net.S)
    (Mtime : module type of Mirage_mtime) =
struct
  (* Adapt Mirage devices to NanoOS device signatures. *)
  module Block_adapter = struct
    type t = Blk.t

    type write_error = Nano_os.Block.error
    type read_error = Nano_os.Block.error

    let pp_write_error = Nano_os.Block.pp_error
    let pp_read_error = Nano_os.Block.pp_error

    let get_info dev =
      let* info = Blk.get_info dev in
      Lwt.return
        {
          Nano_os.Block.size_sectors = info.Mirage_block.size_sectors;
          sector_size = info.sector_size;
          read_write = info.read_write;
        }

    let read dev sector_start bufs =
      let* res = Blk.read dev sector_start bufs in
      match res with
      | Ok () -> Lwt.return (Ok ())
      | Error _ -> Lwt.return (Error `Disconnected)

    let write dev sector_start bufs =
      let* res = Blk.write dev sector_start bufs in
      match res with
      | Ok () -> Lwt.return (Ok ())
      | Error _ -> Lwt.return (Error `Disconnected)

    let connect _ = Lwt.fail_with "Mirage block device is provided by runtime"
    let disconnect _ = Lwt.return_unit
  end

  module Net_adapter = struct
    type t = Netif.t

    let connect _ = Lwt.fail_with "Mirage network device is provided by runtime"
    let disconnect _ = Lwt.return_unit

    (* Minimal Ethernet/IP/UDP framing for Solo5. *)
    let my_ip = "\010\000\000\002" (* 10.0.0.2 *)
    let host_ip = "\010\000\000\001" (* 10.0.0.1 *)
    let my_mac = "\xba\x2d\x86\x66\x65\x2e" (* Arbitrary MAC *)
    let broadcast_mac = "\xff\xff\xff\xff\xff\xff"
    
    (* Mutable reference to store Host MAC (learned from ARP/Input) *)
    let host_mac = ref broadcast_mac

    (* Utility to calculate IP checksum *)
    let checksum_ip cs =
      let sum = ref 0 in
      for i = 0 to (Cstruct.length cs / 2) - 1 do
        sum := !sum + Cstruct.BE.get_uint16 cs (i * 2)
      done;
      let sum = (!sum lsr 16) + (!sum land 0xffff) in
      let sum = sum + (sum lsr 16) in
      lnot sum land 0xffff

    let write dev ~dst:_ payload =
      Printf.printf "[Unikernel] Sending packet (len=%d) to %s\n%!" (Cstruct.length payload) host_ip;
      (* Construct Frame: Eth (14) + IP (20) + UDP (8) + Payload *)
      let payload_len = Cstruct.length payload in
      let total_len = 14 + 20 + 8 + payload_len in
      let buf = Cstruct.create total_len in

      (* 1. Ethernet Header *)
      (* Use learned Host MAC if available, otherwise Broadcast *)
      Cstruct.blit_from_string !host_mac 0 buf 0 6; 
      Cstruct.blit_from_string my_mac 0 buf 6 6;
      Cstruct.BE.set_uint16 buf 12 0x0800; (* EtherType IP *)

      (* 2. IP Header *)
      Cstruct.set_uint8 buf 14 0x45; (* Version 4, IHL 5 *)
      Cstruct.set_uint8 buf 15 0x00; (* TOS *)
      Cstruct.BE.set_uint16 buf 16 (20 + 8 + payload_len); (* Total Length *)
      Cstruct.BE.set_uint16 buf 18 0x0000; (* ID *)
      Cstruct.BE.set_uint16 buf 20 0x0000; (* Flags/Frag *)
      Cstruct.set_uint8 buf 22 64; (* TTL *)
      Cstruct.set_uint8 buf 23 17; (* Protocol UDP *)
      Cstruct.BE.set_uint16 buf 24 0x0000; (* Checksum placeholder *)
      Cstruct.blit_from_string my_ip 0 buf 26 4;
      Cstruct.blit_from_string host_ip 0 buf 30 4;
      
      (* Calculate IP Checksum *)
      let ip_header = Cstruct.sub buf 14 20 in
      Cstruct.BE.set_uint16 buf 24 (checksum_ip ip_header);

      (* 3. UDP Header *)
      Cstruct.BE.set_uint16 buf 34 8080; (* Src Port *)
      let dst_port = 1234 in (* Assumption: Client binds to 1234. Ideally parse dst param *)
      Cstruct.BE.set_uint16 buf 36 dst_port; 
      Cstruct.BE.set_uint16 buf 38 (8 + payload_len); (* Length *)
      Cstruct.BE.set_uint16 buf 40 0x0000; (* Checksum Optional *)

      (* 4. Payload *)
      Cstruct.blit payload 0 buf 42 payload_len;

      let* res = Netif.write dev ~size:total_len (fun b -> Cstruct.blit buf 0 b 0 total_len; total_len) in
      match res with
      | Ok () -> Lwt.return (Ok ())
      | Error e -> Lwt.return (Error (`Unknown (Format.asprintf "%a" Netif.pp_error e)))

    let listen dev callback =
      let header_size = 14 in
      Lwt.catch
        (fun () ->
          let* res = Netif.listen dev ~header_size (fun buf ->
            (* Analyze Packet *)
            if Cstruct.length buf < 14 then Lwt.return_unit
            else
              let ethertype = Cstruct.BE.get_uint16 buf 12 in
              match ethertype with
              | 0x0806 -> (* ARP *)
                  if Cstruct.length buf >= 42 then
                    let opcode = Cstruct.BE.get_uint16 buf 20 in
                    let target_ip = Cstruct.sub buf 38 4 in
                    if opcode = 1 && Cstruct.to_string target_ip = my_ip then (
                       Printf.printf "[Unikernel] ARP Request received for 10.0.0.2!\n%!"; 
                      (* Learn Host MAC *)
                      let src_mac = Cstruct.sub buf 6 6 in
                      if !host_mac = broadcast_mac then (
                           host_mac := Cstruct.to_string src_mac;
                           Printf.printf "[Unikernel] Learned Host MAC!\n%!"
                      );

                      (* It's a request for me. Reply! *)
                      let reply = Cstruct.create 42 in
                      let src_ip = Cstruct.sub buf 28 4 in (* Request Sender IP *)
                      
                      (* Eth Header *)
                      Cstruct.blit src_mac 0 reply 0 6; (* Dst = Requestor *)
                      Cstruct.blit_from_string my_mac 0 reply 6 6; (* Src = Me *)
                      Cstruct.BE.set_uint16 reply 12 0x0806;

                      (* ARP Payload *)
                      Cstruct.BE.set_uint16 reply 14 1; (* Hardware Type Eth *)
                      Cstruct.BE.set_uint16 reply 16 0x0800; (* Proto IP *)
                      Cstruct.set_uint8 reply 18 6; (* HW Addr Len *)
                      Cstruct.set_uint8 reply 19 4; (* Proto Addr Len *)
                      Cstruct.BE.set_uint16 reply 20 2; (* Opcode Reply *)
                      
                      Cstruct.blit_from_string my_mac 0 reply 22 6;
                      Cstruct.blit_from_string my_ip 0 reply 28 4;
                      Cstruct.blit src_mac 0 reply 32 6; (* Target = Requestor *)
                      Cstruct.blit src_ip 0 reply 38 4;

                      let* _ = Netif.write dev ~size:42 (fun b -> Cstruct.blit reply 0 b 0 42; 42) in
                      Lwt.return_unit
                    ) else Lwt.return_unit
                  else Lwt.return_unit
              | 0x0800 -> (* IP *)
                  if Cstruct.length buf >= 34 then
                     let proto = Cstruct.get_uint8 buf 23 in
                     if proto = 17 then (* UDP *)
                        let ip_header_len = (Cstruct.get_uint8 buf 14 land 0x0F) * 4 in
                        let udp_start = 14 + ip_header_len in
                        if Cstruct.length buf >= udp_start + 8 then
                          let _src_port = Cstruct.BE.get_uint16 buf udp_start in
                          let dst_port = Cstruct.BE.get_uint16 buf (udp_start + 2) in
                          let len = Cstruct.BE.get_uint16 buf (udp_start + 4) in
                          let payload_len = len - 8 in
                          if dst_port = 8080 then (
                             Printf.printf "[Unikernel] Received UDP packet on 8080 (len=%d)!\n%!" payload_len;
                             (* Learn Host MAC from IP packet too *)
                             let src_mac = Cstruct.sub buf 6 6 in
                             if !host_mac = broadcast_mac then host_mac := Cstruct.to_string src_mac;
                             
                             let payload = Cstruct.sub buf (udp_start + 8) payload_len in
                             callback payload
                          ) else Lwt.return_unit
                        else Lwt.return_unit
                     else Lwt.return_unit
                  else Lwt.return_unit
              | _ -> Lwt.return_unit
          ) in
          match res with
          | Ok () -> Lwt.return (Ok ())
          | Error e -> Lwt.return (Error (`Unknown (Format.asprintf "%a" Netif.pp_error e))))
        (fun exn -> Lwt.return (Error (`Unknown (Printexc.to_string exn))))
  end

  module Clock_adapter = struct
    type t = unit

    let connect () = Lwt.return ()

    let sleep_s _ seconds =
      let ns = Int64.of_float (seconds *. 1_000_000_000.) in
      Mirage_sleep.ns ns

    let now_ns _ = Mtime.elapsed_ns ()
  end

  module Random_adapter = struct
    type t = Random.State.t

    let connect () = Lwt.return (Random.State.make_self_init ())

    let int state bound = Random.State.int state bound

    let float state bound = Random.State.float state bound
  end

  module Platform = struct
    module Block = Block_adapter
    module Net = Net_adapter
    module Clock = Clock_adapter
    module Random = Random_adapter
  end

  module App = Nano_os.App.Make (Platform)

  let port = 8080

  let start block net _mtime =
    let* random = Random_adapter.connect () in
    let* clock = Clock_adapter.connect () in
    App.boot_with_devices
      ~disk:block
      ~net
      ~clock
      ~random
      ~port
      ()
end
