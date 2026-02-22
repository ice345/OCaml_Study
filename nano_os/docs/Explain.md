好的！我已经把 `nano_os` 项目的所有源文件都读完了。下面我来**从零开始、逐层逐文件**为你详细讲解这个项目。内容较多，我会分成多个部分，并对所有用到的高级语法做专门解释。

---

# 🧭 NanoOS 项目总览

> **NanoOS** 是一个用 OCaml 编写的**教学型 unikernel 模拟器**。  
> 你可以把它理解为：**一个精简的"类操作系统"服务端**，通过 UDP 网络接收命令（如 `ls`、`cat`、`write`），操作一个虚拟文件系统，然后把结果发回给客户端。

### 整体架构图

```
Client (bin/client.ml)
    │  发送 UDP 命令（如 "ls"）
    │
    ▼
Stack（可靠传输层：ACK + 重试 + 去重）
    │
    ▼
Unikernel（命令处理主循环）
    │
    ├── Shell（解析命令字符串）
    │       │
    │       ▼
    │     FS（文件系统操作）
    │           │
    │           ▼
    │         Block（磁盘块设备）
    │
    ▼
Stack.send（把结果通过网络发回客户端）
```

### 目录结构一览

```
nano_os/
├── lib/                    ← 核心库（平台无关）
│   ├── block.ml/mli        ← 块设备接口
│   ├── ram_disk.ml         ← 内存块设备（测试用）
│   ├── fs.ml               ← 文件系统
│   ├── net.mli             ← 网络设备接口
│   ├── clock.mli           ← 时钟接口
│   ├── nano_random.mli     ← 随机数接口
│   ├── packet.ml           ← 协议编解码
│   ├── stack.ml            ← 可靠传输层
│   ├── shell.ml            ← 命令解析器
│   ├── unikernel.ml        ← 主循环
│   ├── app.ml              ← 平台无关启动装配
│   ├── nano_os.ml          ← 库入口（re-export）
│   └── unix/               ← Unix 平台实现
│       ├── file_disk.ml    ← 文件块设备
│       ├── socket_net.ml   ← UDP 网络
│       ├── clock_unix.ml   ← Unix 时钟
│       ├── random_unix.ml  ← Unix 随机数
│       └── platform_unix.ml← 平台组装
├── bin/
│   ├── main.ml             ← 服务端入口
│   └── client.ml           ← 客户端入口
├── test/
│   └── test_nano_os.ml     ← 单元测试
└── mirage/                 ← Mirage 平台（跨平台部署）
    ├── config.ml
    └── unikernel.ml
```

---

# 📦 第一层：接口定义文件（.mli）

`.mli` 文件只写"类型签名"，不写实现，相当于 C 的头文件，告诉外界"这个模块能用什么"。

---

## 1. `lib/block.ml` — 块设备接口

```ocaml name=nano_os/lib/block.ml url=https://github.com/ice345/OCaml_Study/blob/0da0d52edcceabef6ef99e765deb9ea6c6012b86/nano_os/lib/block.ml
type error = [
  | `Disconnected
  | `Is_read_only
  | `Out_of_bounds of int64
]

let pp_error ppf = function
  | `Disconnected -> Fmt.string ppf "Disk is disconnected"
  | `Is_read_only -> Fmt.string ppf "Disk is read-only"
  | `Out_of_bounds sector -> Fmt.pf ppf "Out of bounds: sector %Ld" sector

type info = {
  size_sectors : int64;
  sector_size : int;
  read_write : bool;
}

module type BLOCK = sig
  type t
  type write_error = error
  type read_error = error

  val get_info : t -> info Lwt.t
  val read : t -> int64 -> Cstruct.t list -> (unit, read_error) result Lwt.t
  val write : t -> int64 -> Cstruct.t list -> (unit, write_error) result Lwt.t
  val connect : string -> t Lwt.t
  val disconnect : t -> unit Lwt.t
end
```

### 🔍 高级语法解释

#### ① 多态变体（Polymorphic Variants）：`` `Disconnected ``
```ocaml
type error = [ `Disconnected | `Is_read_only | `Out_of_bounds of int64 ]
```
- 用反引号 `` ` `` 开头的构造器叫**多态变体**，与普通变体的区别在于：
  - **不需要预先声明在哪个类型里**，可以被多个类型共享
  - 非常适合错误码，因为不同层可以用 `[ error_A | error_B ]` 组合起来

#### ② `Cstruct.t` — 二进制缓冲区
- 来自 `cstruct` 库，类似 C 中的 `char*` + 长度，专门用来操作二进制数据
- 磁盘读写都用 `Cstruct.t list`（缓冲区列表），这是硬件驱动的惯例（scatter-gather I/O）

#### ③ `module type BLOCK = sig ... end` — 模块类型（接口）
- 这是 OCaml 的**模块类型**，等价于面向对象里的"接口/Interface"
- 凡是满足这个接口的模块，都可以当作 `BLOCK` 来用（鸭子类型的模块版本）

#### ④ `(unit, error) result Lwt.t` — 异步结果类型
- `result` = `Ok 值 | Error 错误`
- `Lwt.t` = 异步 Promise（类似 JavaScript 的 `Promise<T>`）
- 组合起来就是：**一个"将来会完成"的操作，成功返回 `()`，失败返回 `error`**

---

## 2. `lib/clock.mli` 和 `lib/nano_random.mli` — 时钟与随机数接口

```ocaml name=nano_os/lib/clock.mli url=https://github.com/ice345/OCaml_Study/blob/0da0d52edcceabef6ef99e765deb9ea6c6012b86/nano_os/lib/clock.mli
module type S = sig
  type t
  val connect : unit -> t Lwt.t
  val sleep_s : t -> float -> unit Lwt.t
  val now_ns : t -> int64
end
```

```ocaml name=nano_os/lib/nano_random.mli url=https://github.com/ice345/OCaml_Study/blob/0da0d52edcceabef6ef99e765deb9ea6c6012b86/nano_os/lib/nano_random.mli
module type S = sig
  type t
  val connect : unit -> t Lwt.t
  val int : t -> int -> int
  val float : t -> float -> float
end
```

这两个是非常简洁的**抽象接口**：
- `Clock.S`：能连接、能睡眠（异步等待）、能获取当前纳秒时间
- `Nano_random.S`：能连接、能生成随机整数/浮点数
- **为什么要抽象？** 在 Unix 上用 `Unix.gettimeofday()`，在 Mirage（裸机）上用内核时钟，接口相同，实现不同

---

## 3. `lib/net.mli` — 网络设备接口

```ocaml name=nano_os/lib/net.mli url=https://github.com/ice345/OCaml_Study/blob/0da0d52edcceabef6ef99e765deb9ea6c6012b86/nano_os/lib/net.mli
type error = [ `Disconnected | `Unknown of string ]

val pp_error : Format.formatter -> error -> unit

module type NETWORK = sig
  type t
  val connect : string -> t Lwt.t
  val disconnect : t -> unit Lwt.t
  val write : t -> dst:string -> Cstruct.t -> (unit, error) result Lwt.t
  val listen : t -> (Cstruct.t -> unit Lwt.t) -> (unit, error) result Lwt.t
end
```

### 🔍 高级语法解释

#### `~dst:string` — 标签参数（Labeled Arguments）
```ocaml
val write : t -> dst:string -> Cstruct.t -> ...
```
- `~dst` 是**有名字的参数**，调用时可以写 `write net ~dst:"8080" buf`
- 好处：函数参数多时不容易搞混顺序，代码可读性更强

#### `(Cstruct.t -> unit Lwt.t)` — 回调函数类型
- `listen` 接收一个**回调函数**，每当收到数据包就调用它
- 这是事件驱动编程的核心模式

---

# 🧱 第二层：核心实现文件

## 4. `lib/ram_disk.ml` — 内存块设备

```ocaml name=nano_os/lib/ram_disk.ml url=https://github.com/ice345/OCaml_Study/blob/0da0d52edcceabef6ef99e765deb9ea6c6012b86/nano_os/lib/ram_disk.ml
type t = {
  data : Cstruct.t;
  info : Block.info;
}

let connect _name = 
  let size_bytes = 1024 * 1024 in  (* 1MB *)
  let data = Cstruct.create size_bytes in
  let size_sectors = Int64.of_int (size_bytes / sector_size) in
  let info = { Block.size_sectors; Block.sector_size; Block.read_write = true } in
  Lwt.return { data; info }
```

**这是一个纯内存的"假磁盘"**，用一块 1MB 的连续内存模拟扇区读写，主要供测试使用。

### 🔍 读写实现中的递归

```ocaml
let rec copy_loop src = function
  | [] -> ()
  | dst :: rest ->
      let len = Cstruct.length dst in
      Cstruct.blit curr_src 0 dst 0 len;
      copy_loop next_src rest
```

- `function` = `fun x -> match x with`
- 这是**尾递归**遍历缓冲区列表，依次把 `src` 的数据拷贝进每个 `dst`

---

## 5. `lib/fs.ml` — 文件系统（最核心的模块）

这个文件是整个项目最复杂的部分，实现了一个**简单的平坦文件系统**（类似 FAT，但更简单）。

### 磁盘布局（On-disk Layout）

```
扇区 0 开始：
┌─────────────────────────────────────┐
│  Superblock（16 bytes）              │
│  magic(8) | count(4) | next_free(4)  │
├─────────────────────────────────────┤
│  Directory Entry 0（64 bytes）        │
│  name(56) | start(4) | size(4)       │
├─────────────────────────────────────┤
│  Directory Entry 1                   │
│  ...（最多 32 个文件）                │
├─────────────────────────────────────┤
│  数据区（文件内容从此开始）            │
└─────────────────────────────────────┘
```

### 模块定义结构

```ocaml name=nano_os/lib/fs.ml url=https://github.com/ice345/OCaml_Study/blob/0da0d52edcceabef6ef99e765deb9ea6c6012b86/nano_os/lib/fs.ml#L17-L33
module type S = sig
  type t
  type block_t

  val format : t -> (unit, error) result Lwt.t
  val create_file : t -> string -> string -> (unit, error) result Lwt.t
  val write_file : t -> string -> string -> (unit, error) result Lwt.t
  val read_file : t -> string -> (string, error) result Lwt.t
  val ls : t -> string list Lwt.t
  val delete_file : t -> string -> (unit, error) result Lwt.t

  val connect : ?repair:bool -> block_t -> t Lwt.t
  val is_formatted : t -> bool Lwt.t
end

module Make (B : Block.BLOCK) : S with type block_t = B.t = struct
  ...
end
```

### 🔍 高级语法解释

#### ① `module Make (B : Block.BLOCK) : S with type block_t = B.t`
这是 OCaml 最重要的高级特性之一 —— **Functor（函子）**���

```
module Make (B : Block.BLOCK) = ...
         ↑                ↑
     参数名称         参数必须满足的接口
```

- **Functor 就是"以模块为参数的函数"**
- `Make(RamDisk)` → 生成一个用内存磁盘的文件系统
- `Make(File_disk)` → 生成一个用文件磁盘的文件系统
- `: S with type block_t = B.t` 是**约束返回类型**，告诉编译器"返回的模块满足接口 S，并且 block_t 就是 B.t"

#### ② `?repair:bool` — 可选参数
```ocaml
val connect : ?repair:bool -> block_t -> t Lwt.t
```
- `?` 开头表示**可选参数**，不传时有默认值（这里默认是 `false`）
- 调用时可以写 `FS.connect disk` 或 `FS.connect ~repair:true disk`

#### ③ Hashtbl 缓存
```ocaml
type t = {
  disk : B.t;
  info : Block.info;
  cache : (string, int32 * int32) Hashtbl.t;  (* 文件名 -> (起始扇区, 大小) *)
}
```
- 每次读目录都要读磁盘很慢，所以用哈希表缓存文件名到位置的映射
- `(string, int32 * int32)` 表示键是 `string`，值是 `int32 * int32`（元组）

---

## 6. `lib/packet.ml` — 协议编解码

这个模块定义了客户端和服务端之间通信的**二进制包格式**：

```
包格式（字节）：
[0]   version     (1 byte)
[1]   kind        (1 byte, 0=Data, 1=Ack)
[2]   seq         (1 byte, 序列号 0-255)
[3]   ack         (1 byte, 确认号)
[4-5] src_port    (2 bytes, Little-Endian)
[6-7] payload_len (2 bytes, Little-Endian)
[8-9] checksum    (2 bytes, Little-Endian)
[10+] payload     (可变长度)
```

```ocaml name=nano_os/lib/packet.ml url=https://github.com/ice345/OCaml_Study/blob/0da0d52edcceabef6ef99e765deb9ea6c6012b86/nano_os/lib/packet.ml#L1-L48
type kind = Data | Ack

type t = {
  version : int;
  kind : kind;
  seq : int;
  ack : int;
  src_port : int;
  payload : string;
}

let checksum_bytes (bytes : bytes) =
  let sum = ref 0 in
  for i = 0 to Bytes.length bytes - 1 do
    sum := (!sum + Char.code (Bytes.get bytes i)) land 0xFFFF
  done;
  !sum
```

### 🔍 高级语法解释

#### ① `(bytes : bytes)` — 类型标注
在参数后面加 `: 类型` 是显式类型标注，帮助编译器和读者理解，尤其当函数名 `bytes` 容易混淆时

#### ② `ref` / `!` / `:=` — 可变引用
```ocaml
let sum = ref 0        (* 创建可变引用，初始值 0 *)
sum := !sum + x        (* := 是赋值，!sum 是解引用（读取值）*)
```
OCaml 默认一切不可变，`ref` 是"显式引入可变状态"的方式

#### ③ `land 0xFFFF` — 位与运算，限制在 16 位范围

#### ④ 校验和算法（Checksum）
把头部字节逐个加起来，结果对 65536 取模，用于检测数据损坏

---

## 7. `lib/stack.ml` — 可靠传输层（重点！）

这是项目最"高级"的模块，实现了类似 TCP 的可靠 UDP 传输：

```ocaml name=nano_os/lib/stack.ml url=https://github.com/ice345/OCaml_Study/blob/0da0d52edcceabef6ef99e765deb9ea6c6012b86/nano_os/lib/stack.ml#L34-L80
module Make (N : Net.NETWORK) (C : Clock.S) (R : Nano_random.S) = struct
  type t = {
    net : N.t;
    clock : C.t;
    random : R.t;
    my_port : int;
    mutable next_seq : int;
    pending_acks : (int, unit Lwt.u) Hashtbl.t;  (* seq -> 等待唤醒器 *)
    seen_data : ((int * int), int64) Hashtbl.t;   (* (src_port,seq) -> 时间戳 *)
    config : config;
  }
```

### 🔍 高级语法解释

#### ① 三参数 Functor
```ocaml
module Make (N : Net.NETWORK) (C : Clock.S) (R : Nano_random.S) = struct
```
- 接受**三个模块参数**：网络、时钟、随机数
- 使得 Stack 完全不依赖具体平台实现

#### ② `mutable` 字段
```ocaml
mutable next_seq : int;
```
- OCaml record 字段默认不可变，加 `mutable` 才能修改
- 序列号需要每次发包后递增，所以必须可变

#### ③ `Lwt.wait()` 和 `Lwt.wakeup_later` — Lwt Promise 机制
```ocaml
let waiter, awakener = Lwt.wait () in
Hashtbl.add t.pending_acks seq awakener;
(* ... 稍后在收到 ACK 时 ... *)
Lwt.wakeup_later wakener ();
```
- `Lwt.wait()` 创建一对 `(等待方, 唤醒方)`
- 发包时把 `awakener` 存进哈希表
- 收到 ACK 时查找对应 `awakener` 并调用，从而唤醒等待的发包协程
- 这就是 **Promise/Resolve 模式**在 OCaml 中的实现

#### ④ `Lwt.pick` — 竞争两个 Promise，先完成的赢
```ocaml
let* result = Lwt.pick [ timeout; acked ] in
```
- `timeout`：等待一段时间后返回 `` `Timeout ``
- `acked`：等待 ACK 后返回 `` `Acked ``
- 先到先赢，另一个被取消

#### ⑤ 指数退避（Exponential Backoff）
```ocaml
let base = t.config.initial_timeout_s *. (2. ** float_of_int attempt) in
```
- 第 0 次：等 0.2s
- 第 1 次：等 0.4s
- 第 2 次：等 0.8s
- 这是网络重传的标准策略

#### ⑥ 去重（Deduplication）
```ocaml
seen_data : ((int * int), int64) Hashtbl.t   (* (发送方端口, 序列号) -> 收到时间 *)
```
- 记录最近收到的每个包，防止重复处理（因为发送方可能重传同一个包）

---

## 8. `lib/shell.ml` — 命令解析器

```ocaml name=nano_os/lib/shell.ml url=https://github.com/ice345/OCaml_Study/blob/0da0d52edcceabef6ef99e765deb9ea6c6012b86/nano_os/lib/shell.ml#L9-L63
module Make (FS : Fs.S) = struct
  type t = FS.t

  let eval fs cmd_str =
    let parts = String.split_on_char ' ' cmd_str |> List.filter (fun s -> s <> "") in
    match parts with
    | [] -> Lwt.return ""
    | command :: args ->
        let command = String.lowercase_ascii command in
        (match (command, args) with
        | "ls", [] -> ...
        | "cat", [ filename ] -> ...
        | "write", filename :: words -> ...
        | "rm", [ filename ] -> ...
        | _ -> Lwt.return ("Unknown command: " ^ cmd_str))
end
```

### 🔍 高级语法解释

#### ① `|>` 管道操作符
```ocaml
String.split_on_char ' ' cmd_str |> List.filter (fun s -> s <> "")
```
- `f x |> g` 等价于 `g (f x)`
- 从左到右读：先分割字符串，再过滤空字符串

#### ② 模式匹配列表结构
```ocaml
| command :: args ->        (* 头部 :: 尾部 *)
| "cat", [ filename ] ->    (* 匹配恰好一个元素的列表 *)
| "write", filename :: words -> (* 至少一个元素 *)
```
- `::` 是 cons，匹配"非空列表"
- `[ x ]` 匹配"恰好一个元素的列表"
- 同时匹配元组 `(command, args)` 非常简洁

---

## 9. `lib/unikernel.ml` — 主循环

```ocaml name=nano_os/lib/unikernel.ml url=https://github.com/ice345/OCaml_Study/blob/0da0d52edcceabef6ef99e765deb9ea6c6012b86/nano_os/lib/unikernel.ml
module Make (Fs_mod : Fs.S) (Stack_mod : Stack.S) = struct
  module Shell_mod = Shell.Make (Fs_mod)

  let run fs net_dev =
    let* listen_res =
      Stack_mod.listen net_dev (fun port payload ->
          Lwt.async (fun () ->
            let* response = Shell_mod.eval fs payload in
            let* send_res = Stack_mod.send net_dev port response in
            match send_res with
            | Ok () -> Lwt.return_unit
            | Error _ -> Lwt.return_unit);
          Lwt.return_unit)
    in
    match listen_res with
    | Ok () -> Lwt.return_unit
    | Error _ -> Lwt.return_unit
end
```

### 运行逻辑
1. `Stack_mod.listen` 开始监听网络
2. 每收到一个命令 `payload`，**异步**（`Lwt.async`）地处理它
3. 用 `Shell_mod.eval` 解析并执行命令
4. 用 `Stack_mod.send` 把结果发回给发送方端口

### 🔍 `let*` — Lwt 的 `bind` 语法糖
```ocaml
open Lwt.Syntax

let* x = some_lwt_action () in
do_something_with x
```
- `let*` 来自 `open Lwt.Syntax`
- 等价于 `some_lwt_action () >>= fun x -> do_something_with x`
- 本质是异步链式调用，像在写同步代码一样写异步逻辑

---

## 10. `lib/app.ml` — 平台无关启动装配

```ocaml name=nano_os/lib/app.ml url=https://github.com/ice345/OCaml_Study/blob/0da0d52edcceabef6ef99e765deb9ea6c6012b86/nano_os/lib/app.ml
module type PLATFORM = sig
  module Block : Block.BLOCK
  module Net : Net.NETWORK
  module Clock : Clock.S
  module Random : Nano_random.S
end

module Make (P : PLATFORM) = struct
  module Fs_impl = Fs.Make (P.Block)
  module Stack_impl = Stack.Make (P.Net) (P.Clock) (P.Random)
  module Kernel = Unikernel.Make (Fs_impl) (Stack_impl)

  let boot ?(stack_config = Stack.default_config) ~disk ~port () =
    let* disk_dev = P.Block.connect disk in
    let* net = P.Net.connect port in
    let* clock = P.Clock.connect () in
    let* random = P.Random.connect () in
    boot_with_devices ~stack_config ~disk:disk_dev ~net ~clock ~random ~port:port_i ()
end
```

### 🔍 模块嵌套 Functor
```
App.Make(Platform_unix)
    ↓
  内部自动装配：
  Fs_impl   = Fs.Make(Platform_unix.Block)
  Stack_impl = Stack.Make(Platform_unix.Net)(Platform_unix.Clock)(Platform_unix.Random)
  Kernel    = Unikernel.Make(Fs_impl)(Stack_impl)
```
只需传入一个"平台模块"，所有组件自动连线 —— 这就是 **Functor 组合**的威力！

---

# 🖥️ 第三层：Unix 平台实现

## 11. `lib/unix/file_disk.ml` — 文件块设备

```ocaml name=nano_os/lib/unix/file_disk.ml url=https://github.com/ice345/OCaml_Study/blob/0da0d52edcceabef6ef99e765deb9ea6c6012b86/nano_os/lib/unix/file_disk.ml#L20-L43
let connect name =
  let flags = [Unix.O_RDWR; Unix.O_CREAT] in
  let* fd = Lwt_unix.openfile name flags 0o644 in
  let* stats = Lwt_unix.fstat fd in
  let* size_bytes = 
    if stats.st_size = 0 then (
      let* () = Lwt_unix.ftruncate fd (1024 * 1024) in
      Lwt.return (1024 * 1024)
    ) else Lwt.return stats.st_size 
  in
  Lwt.return { fd; info }
```

- 打开磁盘文件（如 `nano_disk.img`）
- 如果是空文件，先扩展到 1MB
- 之后按扇区（512字节）随机读写

## 12. `lib/unix/socket_net.ml` — UDP 网络

```ocaml name=nano_os/lib/unix/socket_net.ml url=https://github.com/ice345/OCaml_Study/blob/0da0d52edcceabef6ef99e765deb9ea6c6012b86/nano_os/lib/unix/socket_net.ml
let connect port_str =
  let port = int_of_string port_str in
  let sock = Lwt_unix.socket Lwt_unix.PF_INET Lwt_unix.SOCK_DGRAM 0 in
  let addr = Lwt_unix.ADDR_INET (Unix.inet_addr_any, port) in
  let* () = Lwt_unix.bind sock addr in
  Lwt.return { sock; addr }

let listen t callback =
  let buffer = Bytes.create 4096 in
  let rec loop () =
    let* (len, _sender) = Lwt_unix.recvfrom t.sock buffer 0 4096 [] in
    let packet = Cstruct.of_string (Bytes.sub_string buffer 0 len) in
    Lwt.async (fun () -> callback packet);
    loop ()    (* 尾递归，永远循环 *)
  in
  Lwt.catch (fun () -> loop ()) (fun exn -> ...)
```

- 监听 UDP 端口
- 每收到一个包，`Lwt.async` 异步调用回调，然后立刻继续等下一个包
- `let rec loop ()` + `loop ()` 是事件循环的经典写法

## 13. `lib/unix/platform_unix.ml` — 平台拼装

```ocaml name=nano_os/lib/unix/platform_unix.ml url=https://github.com/ice345/OCaml_Study/blob/0da0d52edcceabef6ef99e765deb9ea6c6012b86/nano_os/lib/unix/platform_unix.ml
open Nano_os

module Block = File_disk
module Net = Socket_net
module Clock = Clock_unix
module Random = Random_unix

(* 匿名模块验证：编译时检查 platform_unix 满足 App.PLATFORM 接口 *)
module _ : App.PLATFORM
  with module Block = Block
   and module Net = Net
   and module Clock = Clock
   and module Random = Random =
struct
  module Block = Block
  module Net = Net
  module Clock = Clock
  module Random = Random
end
```

### 🔍 `module _ : SomeType = struct ... end` — 编译期接口检查
- `module _` 是**匿名模块**（下划线表示不需要命名）
- 加上 `: App.PLATFORM with ...` 的类型约束，编译器会**在编译时验证**这个平台实现是否完整满足接口
- 如果缺少任何方法，编译直接报错，而不是运行时崩溃

---

# 🚀 第四层：启动入口

## 14. `bin/main.ml` — 服务端

```ocaml name=nano_os/bin/main.ml url=https://github.com/ice345/OCaml_Study/blob/0da0d52edcceabef6ef99e765deb9ea6c6012b86/nano_os/bin/main.ml
module UnixApp = App.Make (Platform_unix)

let boot () =
  let stack_cfg = { Stack.max_retries = 6; initial_timeout_s = 0.2; ... } in
  UnixApp.boot ~stack_config:stack_cfg ~disk:"nano_disk.img" ~port:"8080" ()

let () = Lwt_main.run (boot ())
```

- `Lwt_main.run` 启动 Lwt 事件循环，阻塞直到 `boot()` 完成（实际上永远运行）

## 15. `bin/client.ml` — 客户端

```ocaml name=nano_os/bin/client.ml url=https://github.com/ice345/OCaml_Study/blob/0da0d52edcceabef6ef99e765deb9ea6c6012b86/nano_os/bin/client.ml
module ClientStack = Stack.Make (Socket_net) (Clock_unix) (Random_unix)

let rec repl () =
  let* () = Lwt_io.print "> " in
  let* input = Lwt_io.read_line Lwt_io.stdin in
  if input = "exit" then Lwt.return_unit
  else
    let* _ = ClientStack.send stack 8080 input in
    let* () = Lwt_unix.sleep 0.2 in
    repl ()
```

- 提供一个交互式 REPL（Read-Eval-Print Loop）
- 输入命令 → 发送到服务端 8080 端口 → 等待响应 → 循环

---

# 🧪 第五层：测试

## 16. `test/test_nano_os.ml`

```ocaml name=nano_os/test/test_nano_os.ml url=https://github.com/ice345/OCaml_Study/blob/0da0d52edcceabef6ef99e765deb9ea6c6012b86/nano_os/test/test_nano_os.ml#L1-L55
module MyFS = FS.Make (RamDisk)      (* 用内存磁盘测试，速度快、无副作用 *)
module MyShell = Shell.Make (MyFS)

let with_fs f =
  Lwt_main.run (
    let* disk = RamDisk.connect "test" in
    let* fs = MyFS.connect disk in
    let* _ = MyFS.format fs in
    f fs)

let test_fs_create_and_read () =
  with_fs (fun fs ->
    let* _ = MyFS.create_file fs "hello.txt" "nano-os" in
    let* res = MyFS.read_file fs "hello.txt" in
    Alcotest.(check string) "read content" "nano-os" (Result.get_ok res);
    Lwt.return_unit)
```

- 用 **Alcotest** 框架做单元测试
- 每个测试都用 `with_fs` 创建一个全新的干净内存磁盘，互不干扰
- `Alcotest.(check string)` 是带格式化错误信息的断言

---

# 🌐 第六层：Mirage 平台（跨平台部署）

## 17. `mirage/config.ml` — Mirage 配置

```ocaml name=nano_os/mirage/config.ml url=https://github.com/ice345/OCaml_Study/blob/0da0d52edcceabef6ef99e765deb9ea6c6012b86/nano_os/mirage/config.ml
open Mirage

let main =
  main ~packages "Unikernel.Main"
    (block @-> network @-> mtime @-> job)

let () =
  register "nano_os"
    [ main $ block_of_file "nanodisk" $ default_network $ default_mtime ]
```

- `@->` 是 Mirage 的类型连接符，描述 unikernel 需要的设备类型
- Mirage 工具链会根据 target（hvt/xen）自��生成引导代码

## 18. `mirage/unikernel.ml` — Mirage 设备适配器

把 Mirage 的 `Mirage_block.S` / `Mirage_net.S` 接口**适配成 NanoOS 自定义的接口**：

```ocaml name=nano_os/mirage/unikernel.ml url=https://github.com/ice345/OCaml_Study/blob/0da0d52edcceabef6ef99e765deb9ea6c6012b86/nano_os/mirage/unikernel.ml#L1-L45
module Main (Blk : Mirage_block.S) (Netif : Mirage_net.S) ... = struct
  module Block_adapter = struct
    type t = Blk.t
    let get_info dev =
      let* info = Blk.get_info dev in
      Lwt.return { Nano_os.Block.size_sectors = info.Mirage_block.size_sectors; ... }
    let read dev sector_start bufs =
      let* res = Blk.read dev sector_start bufs in
      match res with Ok () -> Lwt.return (Ok ()) | Error _ -> Lwt.return (Error `Disconnected)
    ...
  end
end
```

---

# 📊 总结：涉及的 OCaml 高级语法汇总

| 语法特性 | 出现位置 | 用途 |
|---|---|---|
| **Functor**（模块函子） | `Fs.Make`, `Stack.Make`, `App.Make` | 参数化模块，实现依赖注入 |
| **module type**（模块类型） | `Block.BLOCK`, `Net.NETWORK`, `App.PLATFORM` | 定义模块接口/契约 |
| **多态变体** `` `Ok `` / `` `Error `` | 所有错误处理 | 灵活可组合的错误码 |
| **Lwt / `let*`** | 几乎所有文件 | 异步编程（协程） |
| **标签参数 `~`** | `write ~dst:`, `boot ~disk:` | 提高函数可读性 |
| **可选参数 `?`** | `connect ?repair:`, `boot ?stack_config:` | 带默认值的参数 |
| **`ref` / `!` / `:=`** | `stack.ml`, `packet.ml` | 显式可变状态 |
| **`mutable` 字段** | `Stack.t.next_seq` | Record 中的可变字段 |
| **`Lwt.wait / wakeup_later`** | `stack.ml` | Promise resolve 模式 |
| **`Lwt.pick`** | `stack.ml` | 并发竞争 |
| **`Lwt.async`** | `unikernel.ml`, `socket_net.ml` | 启动后台任务 |
| **`with type`约束** | `Fs.Make : S with type block_t = B.t` | 暴露模块内部类型 |
| **匿名模块 `module _`** | `platform_unix.ml` | 编译期接口验证 |
| **`|>`管道** | `shell.ml` | 函数组合 |

---

如果你想深入某一个模块（比如 `fs.ml` 的完整写入逻辑，或 `stack.ml` 的去重算法），告诉我，我可以继续展开讲解��
