# NanoOS RoadMap（执行状态）

## 阶段 1：核心内核化（完成）

- [x] 抽出 `Unikernel.Make`，入口只做 wiring
- [x] `Stack` 增加 `max_retries` 和错误回传
- [x] `write` 语义落到 `FS.write_file`

## 阶段 2：协议与存储系统化（完成）

- [x] 引入 `Packet` 模块统一编解码
- [x] 头部增加 `version/length/checksum`
- [x] `FS.connect ~repair:true` 实现挂载自检修复

## 阶段 3：平台无关化（完成）

- [x] 新增 `Clock` 抽象接口
- [x] 新增 `Random` 抽象接口
- [x] `Stack.Make(Net)(Clock)(Random)` 完全依赖注入
- [x] 新增 `App.Make(PLATFORM)` 统一装配
- [x] 新增 `App.boot_with_devices` 支持外部 runtime 注入设备
- [x] Unix 后端补齐 `clock_unix/random_unix/platform_unix`

## 阶段 4：Mirage 多平台接入（完成）

- [x] 新增可执行 Mirage 入口 `mirage/unikernel.ml`
- [x] 新增 Mirage 配置 `mirage/config.ml`
- [x] 保留 Unix 平台入口并与 Mirage 并存
- [x] 文档化构建步骤 `mirage/README.md`
- [ ] 将 Mirage target 构建接入 CI（待下一阶段）

## 下一阶段建议（阶段 5）

1. `Stack` 升级为滑动窗口 + RTT 估计。
2. `FS` 引入日志区（write-ahead log）和恢复流程。
3. 增加故障注入测试：乱序、重复包、部分写失败。
