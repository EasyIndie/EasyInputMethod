# 098 — ADR-215 验收专用数据根：真机验证通过

2026-10-19，A（Intel / macOS 13.7.8）。目的：让**已安装宿主**的真实 IMK 验收不再写入用户真实配置/词库（IT-01 的核心前提）。

## 方法

1. `make macos-fast-reinstall APP=… ARGS=--stop-host` 装 `07bbb2f`（执行 `681fb1c8…`）；
2. `launchctl setenv LAMPYRIS_SUPPORT_DIR /tmp/lampyris-imk-1792409305`（绝对路径）；
3. 用户添加「萤火虫」→ `tissrc select cn.jokerhub.inputmethod.Lampyris.default`；
4. 在自建 TextEdit 文档里输入 `wq`+空格（触发学习写入），再 ⌥T/⌥P（触发配置写入）。

## 结果

| 检查 | 结果 |
|---|---|
| 宿主环境 | `ps eww` 显示 `LAMPYRIS_SUPPORT_DIR=/tmp/lampyris-imk-1792409305` ✔ |
| 私有根 | 出现 `user-dictionary.tsv`(60B) 与 `config.toml`(2067B)；config 里 `punctuation="english"`、`chinese_variant="traditional"`（正是本轮切换写入）✔ |
| 真实目录 | `~/Library/Application Support/Lampyris/` 只有 `uninstalled/`，**没有**新的 `config.toml`/`user-dictionary.tsv` ✔ |
| 还原 | `unsetenv` 后停宿主；把安装时移出的真实数据移回，SHA 与安装前**完全一致**：config `3bc1117c…`、词库 `d6054fc7…` ✔ |
| 收尾 | 输入源 ABC、宿主已停、执行 SHA `681fb1c8…`、`LAMPYRIS_SUPPORT_DIR` 已清空 ✔ |

证据：`platforms/macos/build/acceptance-a-098/`（`00-pre.txt`、`01-reinstall.txt`、`02-select.txt`、`03-isolation-proof.txt`、`04-restore.txt`）。

## 结论与用法

- ADR-215 生效：**一个环境变量即可把已装宿主的数据根（配置 + 词库）重定向到私有目录**，默认行为不变；
- 因此真实 IMK 验收可以在私有根里安全跑（含学习写入），不会碰用户数据；
- 提示：本地验收若**不想动**用户现有数据，换包时用 `--keep-data`（`clean-install` 就不会把真实 config/词库移走）；
  本轮为验证「移出 → 隔离 → 移回」全链路特意用了默认 `--purge-data`，并用 SHA 证明还原无损。
- 注意：`LAMPYRIS_SUPPORT_DIR` 面向本机验收，验收结束必须 `launchctl unsetenv`；它不是用户功能，ADR-215 已写明取舍。

## 下一步（IT-01 剩余）

有了数据隔离，可以开始「真实 IMK 验收」：在私有根 + 自有文档下跑 `run-imk-acceptance.sh` 的等价流程
（打字/选字/Esc/来源标注/状态芯片/配置热更新），仍不碰用户数据；再过「独有身份包注册 / TIS 枚举」与 Safari/Terminal 协议。
