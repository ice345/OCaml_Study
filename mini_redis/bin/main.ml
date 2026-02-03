(** 
  Asynchronous Redis-like server main loop based on Lwt.

  This module implements:
  - A per-connection request handling loop
  - Incremental buffer accumulation
  - Support for TCP packet fragmentation and coalescing
    (i.e. partial reads and request pipelining)
*)

open Lwt.Syntax
open Mini_redis

(** Global in-memory key-value store shared by all connections *)
let store = Store.create ()

(** 
  Main per-connection processing loop.

  Arguments:
  - [ic]: input channel associated with the client socket
  - [oc]: output channel associated with the client socket
  - [accum_buffer]: accumulated unread bytes from previous reads

  The loop follows a classic RESP stream-processing model:
  1. Try to decode and handle as many complete requests as possible
     from [accum_buffer].
  2. If a full request is successfully parsed, immediately process
     the remaining buffer (to support request pipelining).
  3. If the buffer does not contain a complete request, read more
     data from the socket and continue.
*)
let rec handle_loop ic oc accum_buffer =
  match Mini_redis.handle_request store accum_buffer with
  | Ok (response, rest) ->
      (** 
        A complete RESP command was successfully decoded.

        - [response] is the encoded RESP reply to be sent back
        - [rest] contains any remaining bytes after this command

        Important:
        We immediately recurse on [rest] without performing a new
        socket read, because the buffer may already contain additional
        pipelined commands.
      *)
      let* () = Lwt_io.write oc response in
      let* () = Lwt_io.flush oc in
      handle_loop ic oc rest

  | Error "Empty buffer" ->
      (** 
        The buffer is empty or fully consumed.

        No further processing is possible without reading new data
        from the client socket.
      *)
      read_more ic oc accum_buffer

  | Error msg when String.sub msg 0 10 = "Incomplete" ->
      (** 
        The buffer contains a prefix of a valid RESP message, but
        not enough bytes to complete it.

        This commonly occurs due to:
        - TCP packet fragmentation
        - Partial reads from the socket

        In this case, we read more data and append it to the buffer.
      *)
      read_more ic oc accum_buffer

  | Error msg ->
      (** 
        A fatal protocol error occurred.

        This indicates malformed RESP input rather than an incomplete
        message. The current implementation logs the error and may
        choose to close the connection or reset the buffer.
      *)
      Lwt_io.printl ("Protocol Error: " ^ msg)

(** 
  Read additional data from the client socket and append it to
  the accumulated buffer.

  If the peer closes the connection (read length = 0), the loop
  terminates gracefully.
*)
and read_more ic oc old_buffer =
  let temp_buf = Bytes.create 1024 in
  let* len = Lwt_io.read_into ic temp_buf 0 1024 in
  if len = 0 then
    (** Client has closed the connection *)
    Lwt_io.printl "Client disconnected"
  else
    let new_data = Bytes.sub_string temp_buf 0 len in
    (** 
      Append newly read data to the existing buffer and resume
      processing. This preserves unconsumed bytes across reads.
    *)
    handle_loop ic oc (old_buffer ^ new_data)

(** 
  Callback invoked for each accepted client connection.

  A new request-processing loop is spawned for each client.
  All exceptions are caught to prevent crashing the server.
*)
let accept_connection _conn (ic, oc) =
  Lwt.catch
    (fun () -> handle_loop ic oc "")
    (fun _ -> Lwt.return_unit)

(** 
  Start the Redis-like TCP server on the specified port.

  This function:
  - Binds to the given port on all network interfaces
  - Accepts incoming connections asynchronously
  - Runs indefinitely until the process is terminated
*)
let start_server port =
  let addr = Unix.ADDR_INET (Unix.inet_addr_any, port) in
  let* _ =
    Lwt_io.establish_server_with_client_address addr accept_connection
  in
  let* () = Lwt_io.printlf "Redis server started on port %d" port in
  (** Block forever *)
  fst (Lwt.wait ())

(** Program entry point *)
let () =
  Lwt_main.run (start_server 6379)
