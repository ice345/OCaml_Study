# NanoOS

NanoOS 是一个用 OCaml 编写的教学型 unikernel 模拟器，重点演示：
- 模块化设备抽象（Functor + module type）
- Lwt 异步事件循环
- Cstruct 二进制协议与磁盘布局

## 当前阶段状态

- 阶段 1（核心内核化）：已完成
  - `Unikernel.Make` 抽离主循环
  - `Stack` 支持最大重试与错误回传
  - `FS.write_file` 覆盖写语义落到 FS 层
- 阶段 2（协议/存储系统化）：已完成
  - `Packet` 模块统一编解码（版本、长度、校验和）
  - mount 自检 + repair
- 阶段 3（平台无关化）：已完成
  - 新增 `Clock` / `Random` 抽象接口
  - `Stack.Make(Net)(Clock)(Random)` 去除对具体 runtime 的隐式依赖
  - `App.Make(PLATFORM)` 提供统一启动装配
  - `App.boot_with_devices` 支持由外部 runtime 注入设备
- 阶段 4（Mirage 多平台接入）：已完成
  - Unix 平台保留：`lib/unix/platform_unix.ml`
  - Mirage 平台入口新增：`mirage/unikernel.ml` + `mirage/config.ml`

## 架构概览

核心库：
- `lib/block.mli`：块设备接口
- `lib/net.mli`：网络设备接口
- `lib/clock.mli`：时钟抽象
- `lib/nano_random.mli`：随机源抽象
- `lib/fs.ml`：文件系统
- `lib/packet.ml`：协议编解码
- `lib/stack.ml`：可靠传输（ACK + 重试 + 去重）
- `lib/unikernel.ml`：命令处理主循环
- `lib/app.ml`：平台无关启动装配

Unix 后端：
- `lib/unix/file_disk.ml`
- `lib/unix/socket_net.ml`
- `lib/unix/clock_unix.ml`
- `lib/unix/random_unix.ml`
- `lib/unix/platform_unix.ml`

Mirage 后端：
- `mirage/unikernel.ml`
- `mirage/config.ml`

## 运行（Unix 平台）

启动服务端：

```bash
dune exec nano_os
```

另开终端启动客户端：

```bash
dune exec client
```

默认端口：
- server: `8080`
- client: `1234`

## 运行（Mirage 平台）

参考 `mirage/README.md`：
- `hvt`：`mirage configure -t hvt` -> `make depends` -> `dune build` -> `solo5-hvt -- dist/nano_os.hvt`
- `xen`：`mirage configure -t xen` -> `make depends` -> `dune build`

## 命令（大小写不敏感）

- `ls`
- `cat <file>`
- `write <file> <msg>`（不存在则创建，存在则覆盖）
- `touch <file>`
- `rm <file>`
- `help`

## 测试

```bash
dune runtest
```

当前共 10 个 Alcotest 用例，覆盖：
- FS create/read/overwrite/repair
- Shell 行为
- Packet roundtrip/checksum
- Stack 最大重试与 ACK 成功路径

测试文件：`test/test_nano_os.ml`

## 学习入口

- 30 分钟上手：`docs/quickstart_30min.md`
- 路线图：`docs/RoadMap.md`
