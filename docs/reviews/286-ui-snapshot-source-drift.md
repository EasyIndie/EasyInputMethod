# 286 — UI 快照源码清单漂移修复

> 2026-11-15。`make macos-ui-snapshots` 在候选窗新增依赖后编译失败；修复并加回归。

## 1. 现象

```
platforms/macos/Sources/CandidateWindow.swift:1290: error: cannot find 'CaretPlacement' in scope
platforms/macos/Sources/CandidateWindow.swift:448:  error: cannot find 'LearningHints' in scope
```

`scripts/ui-snapshots.sh` 为候选窗/面板各维护一份**硬编码源码清单**。`CandidateWindow.swift`
先后引入 `CaretPlacement`（ADR-301）与 `LearningHints`（ADR-311）后，清单没有同步；
主应用 `build.sh` 与 `dev-preview.sh` 用的是各自完整的清单，所以 `make verify`/CI 一直绿，
只有快速 UI 入口坏掉。

## 2. 修复

- `CANDIDATE_SOURCES` / `PANEL_SOURCES` 补 `CaretPlacement.swift`、`LearningHints.swift`；
- 新增 `platforms/macos/tests/test-ui-snapshots.py`：跑候选窗这一档（源码集合最小、命中缓存约 1 秒），
  断言编译成功且产出非空 PNG。清单再漂移会直接红。

## 3. 结果

- `make macos-ui-snapshots` 重新可用：候选窗 6 张 + 面板 14 张 + 状态 HUD 6 张；
- 离线回归 **68 文件 / 337 例 PASS**；`make verify` PASS（542 产物零网络符号）；
- 快照只离屏渲染，不显示窗口、不读真实配置、不碰已装包。

## 4. 快速本地验收回路（本轮确认）

| 目的 | 命令 | 代价 |
|---|---|---|
| 看候选窗/设置/关于/诊断/状态 HUD | `make macos-ui-snapshots` | 秒级；图片在 `platforms/macos/build/ui-snapshots/` |
| 点菜单/设置/学习区（隔离私有配置） | `make macos-dev` | 启动自有的隔离窗口，不装包、不碰真实数据 |
| 全量离线回归 | `make macos-offline-tests` | 约 50 秒 |
| 需要真实 IMK 行为 | 换包验收（签名+公证） | 需要手动移除/重新添加输入源 |

日常改 UI/功能优先用前两条，不必每次换包。

## 5. 关联

`scripts/ui-snapshots.sh`、`platforms/macos/tests/test-ui-snapshots.py`、ADR-301/311。
