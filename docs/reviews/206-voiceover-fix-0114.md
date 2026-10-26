# 206 0.1.14：候选选择与上屏向辅助技术播报（ADR-291）

## 1. 背景

报告203 的实测：VoiceOver 在候选面板弹出时念「输入编码 wq」，但**方向键换候选、空格上屏都不播报**。探针取证（`axdump`/`axobserve`）已定位：候选窗 AX 树完整，缺的是**变化时的通知**（无 `AXAnnouncementRequested`/`AXSelectedChildrenChanged`）。

本报告记录修复实现、离线验证与候选包身份。**真实 VoiceOver 复听需要装 0.1.14 后进行**（`AXAnnouncementRequested` 只投递给辅助技术进程，探针观察器收不到）。

## 2. 改动（ADR-291）

| 文件 | 改动 |
|---|---|
| `platforms/macos/Sources/CandidateWindow.swift` | 新增纯函数 `CandidateAnnouncement.text(...)`：只在**选中项变化或翻页**时给播报文本（`第N项，字，来源` / `第M页，共K页，…`），新组合与空候选不播报；`announce()` 发 `.announcementRequested` 并对同文本 250ms 去重；候选容器暴露 `accessibilitySelectedChildren` 指向当前选中项，选中变化时 post `.selectedChildrenChanged`；`announcedTexts` 记录本进程实际播报（供离屏断言） |
| `platforms/macos/Sources/InputController.swift` | `commit()` 发完文本后播报「文字，已上屏」（此时面板已隐藏，发在 App 元素上） |
| `platforms/macos/tests/candidate-presentation.swift` | 断言纯函数四种情形 + 驱动 `CandidateWindow.update` 确认播报真的从更新路径发出 |
| `run-local-acceptance.py` / `test-local-acceptance.py` | `candidate` 必测清单与合成用例数 70 → 71（新增 `candidate.announcements`） |
| `docs/决策记录.md` | ADR-291 |

不改可见 UI、键处理、候选顺序与去重；不新增配置项。

## 3. 顺带修掉的两处本机坑（都影响验收本身）

1. **`preview-menu.swift` 的 Option+M 事件构造错误**：`charactersIgnoringModifiers` 也写成了 `"µ"`，于是匹配回落到 `characters(byApplyingModifiers:)`——**当前输入源是「萤火虫」时离线回归 FAIL，是 ABC 时通过**。真实事件是 `characters: "µ"` / `charactersIgnoringModifiers: "m"`；改后两种输入源下都通过。
2. **`tools/release_version.py` 依赖 `tomllib`（3.11+）**：本机 macOS 13 的 `python3` 是 3.9，`build.sh --strict` 在写 Info.plist 时崩。加了只读 `[workspace.package]` 的正则兜底（`tomllib` 仍是主路径）。

## 4. 验证（本机已做）

| 项 | 结果 |
|---|---|
| `make verify` | PASS（fmt/lint/test/deny/verify-no-network） |
| 离线回归 | **50/50 PASS**（含修好的 preview-menu） |
| 本地验收 | **6 套件 / 71 用例 PASS**，含新增 `candidate.announcements`（选中→「第2项…」、翻页→「第2页，共2页…」） |
| `build.sh --strict` | PASS（0 告警，`-dead_strip`/逐架构网络导入检查通过） |
| 预览程序（私有 support 目录 + 真实 FFI） | 键入 `wq` → → → 空格，提交到「像」（证明方向键确实改变了选中项）；`announcedTexts` 记录了选中与翻页播报 |
| CI（PR #184） | check/fuzz/dco/macos 四门禁 PASS，merged `51b34d4` |

## 5. 候选包身份（0.1.14 / build 22）

| 项 | 值 |
|---|---|
| 源码提交 | main `51b34d4af1438c793e4ff035bb865700599d8858` |
| 构建 | `macOS Acceptance Package` run `40272651491`（success，同一提交） |
| ZIP SHA-256 | `c080b93a00c28d40dda210f9572388c553173d34339367163eab12fc73776557`（= 资产 `.sha256`） |
| 源码 tar SHA-256 | `a6db331554ef42480f584ce63eeb2e1bb26433c59807b69524f79c810d410228` |
| 执行文件 SHA-256 | `5e6071acb30079efdc74b731c05d6427691b2ead474e8f03e1ee1f84ec11f8d4` |
| 版本 / 构建 | 0.1.14 / 22 |
| 签名 | `codesign --verify --strict --deep` PASS；`spctl` = `accepted source=Notarized Developer ID` |

**本机仍装 0.1.13**（执行 `c3b533e4…`），未安装 0.1.14、未打 tag、未发 Release。

## 6. 待做（需授权/需人）

1. **安装 0.1.14**（替换 0.1.13）后复听 VoiceOver：换候选是否念新候选、上屏是否念结果；随后重跑受影响的验收（键入/热键/客户端/质量样本）——按“历史 PASS 不继承”的规则，装机后这些都要重跑。
2. 回归确认：`AXSelectedChildren` 是否让 VoiceOver 能直接浏览候选列表（需 VO 实际操作）。
3. 若播报过于频繁（逐字上屏），按 ADR-291 的取舍条款再评估是否只播报词级提交。
