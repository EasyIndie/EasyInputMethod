# 195 0.1.13 在两台设备上的安装与验收

## 1. air（本机，Apple Silicon / macOS 27.0.1）

| 项 | 值 |
|---|---|
| 安装包 | 0.1.13 / build 21，来自 Release 资产的 ZIP（`130f3098…`，与验收产物同 SHA） |
| 执行 SHA | `c3b533e49a584e58e6e4ced14ebcca46fddbae14452e84376ad32d193863d308` |
| 签名 | `codesign --strict --deep` 通过；`spctl` = Notarized Developer ID（2N62934Y28） |
| 自动化验收 | **全 PASS**（`make macos-auto-acceptance`，见报告194 §2）：热键 8 项、五客户端 5/5、160 键 p95 8.68 ms、稳态 10.1 MiB、0 条 TCP/UDP |
| 配置 / 词库 | `config.toml` 保持 `809e2cae…`（mode=mixed、标点中文、半角、简体）；词库持续增长（用户真实输入） |
| 回滚点 | `/tmp/lampyris-rollback-0113-prev/`（旧候选 `a3faf05c…`）与 `/tmp/lampyris-rollback-0112/`（0.1.12 `c09c2d11…`） |

## 2. pro（Intel / macOS 13.7.8，用户 `bot`，经 SSH）

安装（走真实发布 DMG，未用本机构建产物）：

| 步 | 结果 |
|---|---|
| 下载 | `Lampyris-0.1.13-universal.dmg` 9,181,993 B；`.sha256` = `2f22120c20548499504845d884e1a0594682f95321b8af73bff7c16c74c52a35`，本地重算一致 |
| 挂载内容 | `安装萤火虫.app`、`卸载萤火虫.app`、`Lampyris.app`、`安装与卸载说明.txt` |
| 安装前快照 | 0.1.12/build20 执行 `c09c2d11…` 已备份到 `/tmp/lampyris-rollback-0112/` |
| 安装后 | 版本 **0.1.13**、构建 **21**、执行 SHA `c3b533e4…`（**与 air 完全相同**）、`codesign --verify --strict --deep` 通过、`spctl` = Notarized Developer ID |
| 宿主 | 新 PID 85195 运行中 |
| 用户数据 | `config.toml` 仍为 `2bd3fde6…`、词库 474 行（升级未触碰） |
| 空闲观测 | 10 次采样 **0 条 TCP/UDP**，RSS 9.7 MiB，无崩溃报告，输入源条目仍含 `Lampyris.default` |

## 3. pro 上被阻塞的自动化项（需用户在本机操作）

该机 SSH 会话里有两处限制，已逐个确认：

1. **测试窗口无法成为前台**：`open -n` 起的窗口拿不到前台（`frontmost` 一直是 `ghostty`），`keytopid --hid` 的前台校验因此拒绝投递 —— 因此热键与客户端矩阵在 pro 上跑不了。
2. **输入源无法被程序切换**：`imetype --self-post` 里 `TISSelectInputSource` 后 `current_source` 仍是 `com.apple.keylayout.ABC`（macOS 13 对第三方源的会话限制），所以进程内自投递也只能打到 ABC。

结论：pro 的**安装与身份**已核实；**键入类验收**（上屏、热键、客户端）需用户在该机解锁后手动完成，或在该机本地终端跑 `make macos-auto-acceptance`（本地会话具备前台与切源能力）。

> **2026-10-25 补充（报告198）**：已在 pro 的**本机图形会话**里跑完自动化，上述两条限制不成立。首轮三个 FAIL 均为探针/环境问题（读出口竞态、macOS 13 不接受 `data:` URL、RSS 口径），修好后 `make macos-auto-acceptance` 全 PASS（客户端 4/4、p95 2.41 ms、25 次采样 0 外联），`quality-samples.sh` 16/16 PASS。pro 的 30MB 内存口径仍需按 ADR-263 在新启动宿主上复测（需授权重启宿主）。

## 4. 交给用户的手动清单（两台都适用）

1. 系统设置 → 键盘 → 文字输入，确认「萤火虫」在列表并可切换。
2. 五笔打 `wq` 上屏「你」之类；想不起码时用拼音兜底；确认候选窗位置正常。
3. **辅助功能**：开启 VoiceOver，确认候选与上屏可被朗读、不崩溃。
4. **多屏 / 缩放**：外接或切换分辨率后候选窗仍贴近插入点、不跑屏外。
5. **睡眠唤醒**：合盖/睡眠唤醒后直接输入，首键不丢、候选正常。
6. **真实卸载 → 重装**：用 DMG 里的「卸载萤火虫」保留数据卸载，再装回，确认配置与词库仍在。
7. 记录每项结果与设备信息（型号、系统版本、执行 SHA、config SHA、词库行数）。

## 5. 备注

- 两台设备的**执行 SHA 相同**（`c3b533e4…`），即验证的是同一份发布产物，只是架构切片不同。
- pro 的 0.1.12 快照仍在 `/tmp/lampyris-rollback-0112/`，如需回滚可直接换回。
