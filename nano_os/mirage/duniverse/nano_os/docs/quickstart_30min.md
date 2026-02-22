# NanoOS 新手 30 分钟上手

目标：30 分钟内看懂主链路，并掌握 4 个点：
- Functor 组装
- Lwt 事件循环
- Cstruct 协议/磁盘编码
- 平台无关化（Net + Clock + Random）

## 0~5 分钟：先跑起来

```bash
dune exec nano_os
```

新开终端：

```bash
dune exec client
```

输入：

```text
help
write demo hello
cat demo
write demo world
cat demo
rm demo
```

---

## 5~10 分钟：看组装层（像 Mirage 的地方）

先看 `bin/main.ml`：
- `module UnixApp = App.Make (Platform_unix)`
- `UnixApp.boot ...`

你要建立的认知：
- `App.Make` 不关心 Unix 细节，只需要一个实现 `PLATFORM` 的模块。
- `Platform_unix` 负责提供 `Block/Net/Clock/Random` 的具体实现。

---

## 10~17 分钟：Lwt 在链路里怎么流动

关键路径：
1. `ClientStack.send` 发请求（`lib/stack.ml`）
2. `Stack.listen` 在服务端收包并回 ACK
3. `Unikernel.run` 调 `Shell.eval`
4. `Shell` 调 `FS` 读写
5. 响应经 `Stack.send` 返回客户端

Lwt 重点只看三种：
- `let*`：顺序异步
- `Lwt.async`：后台任务（回 ACK、客户端监听）
- `Lwt.pick`：ACK vs timeout 竞速

---

## 17~24 分钟：Cstruct 读写在哪里

### 协议层（`lib/packet.ml`）

当前头部 10 字节：

```text
[version:1][kind:1][seq:1][ack:1][src_port:2][payload_len:2][checksum:2]
```

- `encode_*`：按偏移写字段
- `decode`：做 version/kind/length/checksum 校验

### 存储层（`lib/fs.ml`）

- superblock 记录 `magic/count/next_free`
- 目录项记录 `name/start/size`
- `connect ~repair:true` 会过滤坏项并修复元数据

---

## 24~30 分钟：用测试反向学设计

```bash
dune runtest
```

重点看：
- `stack max retries` / `stack ack success`
- `packet checksum validation`
- `repair invalid superblock`

这些测试就是系统行为契约。

---

## 再下一步

1. 给 `Stack` 增加滑动窗口（当前是 stop-and-wait）。
2. 给 `FS` 增加日志区（crash-safe commit）。
3. 在独立 Mirage 子项目中接入 `mirage/config.ml` 模板。 
