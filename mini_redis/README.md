# Mini Redis in OCaml

A high-performance, concurrent, in-memory key-value store compatible with the Redis protocol (RESP), written entirely in OCaml.

![Build Status](https://img.shields.io/badge/build-passing-brightgreen)
![Language](https://img.shields.io/badge/language-OCaml-orange)
![License](https://img.shields.io/badge/license-MIT-blue)

## 🚀 Overview

This project implements a functional Redis server from scratch. Unlike traditional blocking I/O servers, Mini Redis leverages **Lwt (Lightweight Threads)** for asynchronous concurrency, allowing it to handle thousands of concurrent connections on a single core with minimal overhead.

It features a hand-written **Recursive Descent Parser** for the RESP protocol and implements robust **TCP Framing** strategies to handle packet fragmentation and coalescing (sticky packets).

## 📊 Performance Benchmarks

Running on a standard laptop (Single Core):

```bash
redis-benchmark -p 6379 -c 10 -n 1000 -t set,get
```

| Operation | Throughput (QPS) | Avg Latency |
|-----------|------------------|-------------|
| **SET**   | **71,428**       | 0.12 ms     |
| **GET**   | **111,111**      | 0.08 ms     |

*Achieved >100k QPS, comparable to production-grade C implementations in single-threaded mode.*

## ✨ Key Features

*   **RESP Protocol Support**: Fully compliant parser supporting Arrays, Bulk Strings, Integers, and Errors.
*   **Asynchronous I/O**: Non-blocking event loop based on `Lwt`.
*   **TCP Framing**: Correctly handles partial packets (fragmentation) and multiple commands in one packet (sticky packets).
*   **Type Safety**: Leveraging OCaml's strong type system and ADTs to prevent runtime errors.
*   **Modular Architecture**: Clean separation between the core engine (`lib/`) and the network layer (`bin/`).

## 🛠 Architecture

### 1. The Core Engine (`lib/`)
*   **ADT Modeling**: The Redis protocol is modeled using Algebraic Data Types (`type resp = ...`).
*   **Parser**: A recursive descent parser that converts raw bytes into `command` types (`SET`, `GET`, `PING`).
*   **Store**: An in-memory `Hashtbl` backend.

### 2. The Network Layer (`bin/`)
*   **Event Loop**: Powered by `Lwt_main`.
*   **Connection Handling**: Each client connection is handled by a recursive Lwt promise loop.
*   **Buffering Strategy**: Implements a dynamic accumulation buffer to handle TCP stream irregularities.

## 📦 Usage

### Prerequisites
*   OCaml (>= 4.08)
*   Opam & Dune

### Build & Run
```bash
# Install dependencies
opam install . --deps-only

# Build and start the server
dune exec mini_redis
```

### Test with Redis CLI
```bash
redis-cli -p 6379
127.0.0.1:6379> SET mykey ocaml
OK
127.0.0.1:6379> GET mykey
"ocaml"
```

## 🧪 Testing

The project uses **Alcotest** for unit testing, covering parser edge cases, partial packets, and sticky packets.

```bash
dune runtest
```

---

*This project was created as a special project for studying OCaml system programming and for rehabilitation purposes.*

