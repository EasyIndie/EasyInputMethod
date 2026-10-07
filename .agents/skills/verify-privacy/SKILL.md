---
name: verify-privacy
description: 验证萤火虫输入法"零网络 / 零遥测"的承诺是否被破坏。在提交前、发布前、或改动依赖后使用。
---

# 验证隐私承诺

目标：证明**没有网络能力、没有遥测**。依据 `docs/隐私与安全.md`、`AGENTS.md` 铁律 1。

## 自动检查

```sh
make verify-no-network
```

它做两件事：核心 crate 依赖扫描 + 产物网络符号扫描（见 `scripts/verify-no-network.sh`）。

## 人工核对清单

- [ ] 核心 crate（`ime-core`/`ime-table`/`ime-pinyin`/`ime-dict`/`ime-config`）的 `Cargo.toml` 无网络/遥测依赖；
- [ ] 全仓库 `grep` 无遥测 SDK（`sentry`、`opentelemetry`、`mixpanel`…）与统计上报；
- [ ] 无"用户体验改进计划""匿名统计"等开关（本项目**根本没有**该功能）；
- [ ] 配置只写 `config.toml`，未写 `UserDefaults`/注册表（`docs/配置架构.md` R1）；
- [ ] 若涉及语音（P6）：录音只进内存、模型下载由用户显式触发且 HTTPS+哈希校验。

## 手动抓包（发布前）

- macOS：`nettop -p <pid>` 或 `lsof -p <pid> -i`；
- Linux：`ss -tp`；
- Windows：`netstat -bno`。
- 断言：输入法进程**无外部连接**。

## 失败处理

- 一旦发现联网能力 → **停止**，不要合入；移除依赖或写 ADR 说明为何例外（原则上不允许）。
