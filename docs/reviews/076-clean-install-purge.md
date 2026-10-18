# 076 — 全新安装入口：卸载时清理旧版本数据

2026-10-18。用户要求「实机安装时清理旧版本，让新包全新安装，以默认行为为起点」。本轮给 `uninstall.sh` 加 `--purge-data`，并固定一条全新安装流程；**本轮未在 A/B 执行卸载**（需要用户在场与注销）。

## 问题

- 旧版 `uninstall.sh` 只把 bundle 移入 `uninstalled/bundle.*/`，**保留** `config.toml` 与 `user-dictionary.tsv`（ADR-032 的有意设计）。
- 结果：A/B 的 `config.toml` 里是报告 068 时代写死的显式 `ctrl+shift*`，ADR-209 改默认为 `⌥` 前缀后**不会生效**（显式值优先），实机看到的行为和默认值不一致；学习词库也带着上一轮的记录。
- 想验证「默认行为」就必须能把旧数据移出活动目录，且不能靠手改 `config.toml`（铁律 3 只允许经 ime-config 读写，手工删改更不可审计）。

## 决策：移动，不删除

`platforms/macos/uninstall.sh` 新增 `--purge-data`：

| 步骤 | 行为 |
|---|---|
| `--dry-run`（可与 `--purge-data` 组合） | 只打印计划：bundle 会移到哪、哪些用户数据会被移走；**不要求先退出宿主**，切换前就能看清 |
| 默认（无 `--purge-data`） | 行为不变：只移 bundle，保留 config 与词库 |
| `--input-source-removed --purge-data` | bundle → `uninstalled/bundle.*/`；`config.toml`、`user-dictionary.tsv` → `uninstalled/data.*/`；随后提示重登 |

安全性约束保持不变并加强：

- 仍要求先在系统设置里移除输入源（`--input-source-removed`）；宿主仍在运行时拒绝执行（`pgrep -x Lampyris`）。
- bundle 标识必须是 `cn.jokerhub.inputmethod.Lampyris`；输入法目录、bundle、用户数据目录及数据文件**任一为符号链接即拒绝**。
- 数据是**移动**到备份目录，不删除、不覆盖；不在活动目录留下「显式旧默认值」。
- 不触碰 `~/Library/Preferences`、`UserDefaults` 或第二份配置（铁律 3 不变）。

## 全新安装流程（写进 `docs/发布说明.md` §6 与 `docs/开发工作流.md` 守则 2）

1. 切到 **ABC**；「系统设置 → 键盘 → 文字输入」移除萤火虫。
2. `platforms/macos/uninstall.sh --dry-run --purge-data` 看计划（此步无需退出宿主）。
3. 注销／重新登录，使宿主退出。
4. `platforms/macos/uninstall.sh --input-source-removed --purge-data` → 旧包与旧数据进入 `uninstalled/`。
5. `platforms/macos/install.sh --app <新包>` 安装新签名包，重登后在系统设置里重新添加萤火虫。
6. 首次启动按 Schema 默认值生成配置（当前默认：`⌥M`/`⌥Space`/`⌥P`/`⌥T`/`⌥L`/`⌥,`/`⌥A`，中英为单独 `⇧`），学习词库从空开始。

## 验证

新增 `platforms/macos/tests/test-install.py::UninstallerFreshStart`（3 项，跑在临时 `HOME` 上，`pgrep` 用桩，因此不依赖当前登录是否开着输入法，A/CI 都能跑）：

| 用例 | 断言 |
|---|---|
| `--dry-run --purge-data` | 输出列出 `config.toml` 与「默认值」，bundle 与数据**都还在** |
| 默认卸载 | bundle 移走，`config.toml`/`user-dictionary.tsv` **保留** |
| `--purge-data` 执行 | bundle 移入 `uninstalled/bundle.*`，数据移入 `uninstalled/data.*`，活动目录不再有 config/词库 |

本机（A）实测：

```
$ platforms/macos/uninstall.sh --dry-run --purge-data      # 宿主仍在跑也可预检
将把 …/Input Methods/Lampyris.app 移到 …/uninstalled/bundle.XXXXXX/
将把用户数据移到 …/uninstalled/data.XXXXXX/：config.toml user-dictionary.tsv
之后首次启动按 Schema 默认值全新开始（不删除，只是移出活动目录）
```

`python3 platforms/macos/tests/test-install.py` → 5 项全 PASS；`make verify` 全绿（`make macos-offline-tests` 会连带跑这 3 项）。

## 未做 / 限制

- **没有在 A/B 真机执行**：需要用户在场完成「移输入源 → 注销 → 卸载 → 安装 → 重登加输入源」；我按边界不自动注销。
- 备份目录 `~/Library/Application Support/Lampyris/uninstalled/` 会累积历次 `bundle.*`/`data.*`，需要时由用户手动清理（脚本不自动删除历史备份）。
- 卸载只处理 bundle 与这两个数据文件；`~/Library/Caches`、LaunchServices 注册等由系统自行回收。
