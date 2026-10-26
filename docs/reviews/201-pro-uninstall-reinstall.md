# 201 pro 真实卸载 → 重装（保留数据）

## 1. 目的与授权

RC 清单里「真实卸载→重装（保留数据）」原本归为人工项；用户 2026-10-26 明确授权在 pro 上执行。目标：确认卸载/安装脚本在真机上不丢配置与词库、装回的仍是同一份发布产物，并暴露安装器的实际问题。

环境：pro（Intel x86_64 / macOS 13.7.8 / 用户 `bot`）。证据目录 `/tmp/lampyris-reinstall-evidence/`。

安装包取自重发资产（本机原 DMG 已不在），**校验与 Release 的 `.sha256` 一致**：

| 项 | 值 |
|---|---|
| 资产 | `Lampyris-0.1.13-universal.dmg`，9,181,993 B |
| SHA-256 | `2f22120c20548499504845d884e1a0594682f95321b8af73bff7c16c74c52a35`（= 资产 `.sha256`） |

## 2. 起始状态

| 项 | 值 |
|---|---|
| 执行 SHA | `c3b533e49a584e58e6e4ced14ebcca46fddbae14452e84376ad32d193863d308`（0.1.13 / build 21） |
| `config.toml` | `2bd3fde6…` |
| 词库 | 486 行 / `bf84ced6…` |
| 输入源 | `Lampyris`、`Lampyris.default` 已启用，当前 `Lampyris.default` |
| 宿主 | PID 36685 |

## 3. 卸载

先切回 ABC，再跑 `platforms/macos/uninstall.sh`（`卸载萤火虫.app` 的引擎就是它；GUI 外壳没有 CLI，未点击）。

| 步 | 结果 |
|---|---|
| `--dry-run` | 打印「移到 `…/Lampyris/uninstalled/bundle.XXXXXX/`」「保留配置与词库」 |
| 第一次执行 | **拒绝**：`宿主仍在运行；请注销后重试，或手动移除输入源` —— helper 的 `disable` 在这台机器上没有停掉宿主（TIS 限制，见 §6） |
| 停止宿主后重跑 | 成功：`已移出输入法目录，备份在 …/uninstalled/bundle.6MMjbg`、`配置与词库保留` |

卸载后（`03-post-uninstall.txt`）：

| 项 | 值 |
|---|---|
| 安装目录 | `~/Library/Input Methods` 里已无 `Lampyris.app` |
| 备份 | `…/Lampyris/uninstalled/bundle.6MMjbg/Lampyris.app`，执行 SHA 仍 `c3b533e4…` |
| `config.toml` | `2bd3fde6…`（未变） |
| 词库 | 486 行 / `bf84ced6…`（未变） |
| 输入源 | 只剩 ABC、CharacterPaletteIM（萤火虫两条已移除） |
| 宿主 | 已退出 |

## 4. 重装

用 DMG 里的 `Lampyris.app` 跑 `platforms/macos/install.sh --app "/Volumes/萤火虫/Lampyris.app"`（`安装萤火虫.app` 的引擎同一份），签名/公证/`spctl` 逐项校验均通过后才落盘：

| 项 | 值 |
|---|---|
| `xcrun stapler validate` | `The validate action worked!` |
| `spctl --assess` | `accepted source=Notarized Developer ID` |
| 执行 SHA | **`c3b533e4…`（与卸载前、与 air 完全一致）** |
| 版本 / 构建 | 0.1.13 / 21 |
| `codesign --verify --strict --deep` | PASS |
| `config.toml` | `2bd3fde6…`（未变） |
| 词库 | 486 行 / `bf84ced6…`（**逐字节未变**） |
| 宿主 | 启动成功（PID 69116） |

→ **卸载/重装不丢用户数据，装回的是同一份发布产物。**

## 5. 发现：安装器「已自动注册到输入源」在 macOS 13 上是假成功

`install.sh` 打印 `安装完成，已自动注册到输入源。`，但实测：

- helper 的 `enable` 返回 0，紧接着它自己的 `status` 还报 `enabled …default`；
- 几秒后再查（`LampyrisTIS status`、探针 `tissrc list`）都是空，`defaults read com.apple.HIToolbox AppleEnabledInputSources` 里没有萤火虫；
- 于是输入源需要用户在「系统设置 → 键盘 → 文字输入」手动添加——与报告 095 的结论一致（`TISEnableInputSource` 返回 0 但不生效），ADR-276 里「安装后自动注册+启用」的前提在 macOS 13 上不成立。

**建议（0.1.14，未在本轮改代码）**：安装脚本在 `enable` 之后用 `LampyrisTIS status <bundleID>` 复核，只有真的出现在启用列表里才打印「已自动注册」，否则明确要求“注销/重新登录后手动添加”；`packaging/macos/RELEASE-README.md` 的措辞同步。这样用户不会以为已经装好却按 ⌃Space 没反应。

## 6. 输入源手动添加后的键入复验（已完成）

输入源无法用程序添加（铁律：不写 HIToolbox plist），由用户在「系统设置 → 键盘 → 文字输入」手动添加后复验：

| 项 | 结果 |
|---|---|
| `tissrc list` | `Lampyris`、`Lampyris.default` 已启用，当前 `Lampyris.default` |
| `LampyrisTIS status` | `enabled …default,…Lampyris` |
| `acceptance-preflight.sh` | `ready=true`，`exec_sha` 仍 `c3b533e4…` |
| 键入冒烟 `wq nihao .` ×2 | **2/2 PASS**：`keys_seen=10`、`你你好。`、源 `Lampyris.default` |
| `quality-samples.sh` | **16/16 PASS** |
| 宿主 / 网络 | PID 69116（安装后未再重启）、0 条 TCP/UDP |

最终状态对比：

| 项 | 卸载前 | 重装后 | 复验后 |
|---|---|---|---|
| 执行 SHA | `c3b533e4…` | `c3b533e4…` | `c3b533e4…` |
| `config.toml` | `2bd3fde6…` | `2bd3fde6…` | `2bd3fde6…`（未变） |
| 词库 | 486 行 / `bf84ced6…` | 486 行 / `bf84ced6…` | 486 行 / `58dfbc41…` |
| 输入源 | 萤火虫两条启用 | 需手动添加（§5） | 两条启用，当前 `Lampyris.default` |

词库 SHA 在复验后变化但**行数不变**：文件带计数列（如 `pinyin\tnihao\t你好\t407`），键入会原地累加频次（`show_wubi_learning=true` 是用户有意设置），不是数据损坏。

## 7. 结论

- **卸载→重装（保留数据）在真机上通过**：应用可回滚地移入 `uninstalled/` 备份，配置与词库逐字节保留，装回的是**同一执行 SHA** 的公证包，装回后键入与 16 项质量样本全部正常。
- 唯一需要人工的是**添加输入源**：`install.sh` 的「已自动注册」在 macOS 13 上是假成功（§5），建议 0.1.14 用 `LampyrisTIS status` 复核后再宣布成功。
- 备份仍保留在 `~/Library/Application Support/Lampyris/uninstalled/bundle.6MMjbg/`（执行 SHA `c3b533e4…`），可作回滚点；确认无需回滚后可删。
