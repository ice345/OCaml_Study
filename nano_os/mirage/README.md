# NanoOS Mirage Backend

这个目录提供 NanoOS 的 Mirage 入口，实现了和 Unix 平台并存的多平台模式。

## 当前结构

- `unikernel.ml`：Mirage 设备适配层，把 `Mirage_block` / `Mirage_net` / `Mirage_mtime` 接到 `Nano_os.App.Make`。
- `config.ml`：Mirage 配置文件，可选择 `hvt` / `xen` 等 target 生成镜像。

Unix 平台入口仍然保留：
- `/Volumes/External/code/OCaml/nano_os/bin/main.ml`

## 前置条件

1. 在支持 Mirage target 的环境（建议 Linux）安装 mirage 工具链。
2. 在仓库根目录 pin 当前包：

```bash
cd /Volumes/External/code/OCaml/nano_os
opam pin add nano_os . -y
```

## 兼容性提示（Mirage v4.10.4 + 部分 opam 版本）

如果 `make depends` 报 `repo remove ...` 相关错误（例如把 URL 当成 repo 名处理），可在 `mirage configure` 之后执行一次：

```bash
cd /Volumes/External/code/OCaml/nano_os/mirage
sed -i.bak 's|repo remove opam-overlays https://github.com/dune-universe/opam-overlays.git|-opam repo remove opam-overlays|' Makefile
sed -i.bak 's|repo remove mirage-overlays https://github.com/dune-universe/mirage-opam-overlays.git|-opam repo remove mirage-overlays|' Makefile
```

然后再执行 `make depends`。

推荐使用自动脚本（会执行 configure，并自动添加 dune-universe overlays，同时修补 Makefile + dune.build 兼容性问题）：

```bash
cd /Volumes/External/code/OCaml/nano_os/mirage
./reconfigure.sh hvt   # 或 ./reconfigure.sh xen
```

如果你已经执行过旧脚本并遇到 `opam-monorepo` 提示缺少 dune overlays，可手动执行：

```bash
opam repository add dune-universe git+https://github.com/dune-universe/opam-overlays.git \
  || opam repository set-url dune-universe git+https://github.com/dune-universe/opam-overlays.git
opam repository add dune-universe-mirage git+https://github.com/dune-universe/mirage-opam-overlays.git \
  || opam repository set-url dune-universe-mirage git+https://github.com/dune-universe/mirage-opam-overlays.git
```

## 构建 hvt 镜像

```bash
cd /Volumes/External/code/OCaml/nano_os/mirage
mirage configure -t hvt
make depends
dune build
solo5-hvt -- dist/nano_os.hvt
```

## 构建 xen 镜像

```bash
cd /Volumes/External/code/OCaml/nano_os/mirage
mirage configure -t xen
make depends
dune build
```

然后在 Xen 主机使用生成的 `.xl` 配置启动。

## 版本说明

- 新版 Mirage DSL 使用 `default_mtime` / `default_ptime`，不再提供 `default_time`。
- 当前 `config.ml` 已按新版写法使用 `default_mtime`。

## 说明

- NanoOS 协议端口在 Mirage 入口中默认是 `8080`（见 `unikernel.ml`）。
- 如果你的 Mirage 版本 API 与本目录略有差异，优先调整 `unikernel.ml` 的设备适配函数（核心库 `lib/` 不需要改）。
