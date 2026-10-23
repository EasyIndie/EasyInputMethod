# 143 内存复测无效轮与输入源自动化

## 一、B 项（30MB 复测）本轮无效，不作证据

按固定时点协议（冷态 → 首键 → 六词 → 静置 8s）重新采了一轮，但环境不满足低压力条件：

| 项 | 实测 |
|---|---|
| loadavg | **53.98 / 20.96 / 10.60** |
| swap | used 6.1G / 7.2G |
| 宿主 Writable | resident **849–881K**、swapped **20.3–23.4M**（几乎全被换出） |
| trace | p95 **110.99ms**、max 254.85ms、14 键 ≥16ms（明显受环境干扰） |
| physical/peak | 27.0–28.0M / 29.2M（被换出抬高可信度不足） |

**结论：本轮时延与内存都不可作为产品证据**，30MB 仍未判定；记录在 `acceptance-143/99-invalid.txt`，marker 已删除、宿主已停、源已还原 ABC。

### 下一轮采样的前置条件（写死，避免再浪费一轮）

1. `loadavg1 < 8`；
2. `swap used < 2G`；
3. 无 `xcodebuild` / 大 `swift-frontend` 编译；
4. 宿主为**新启动**进程（marker 必须先写）；
5. 采样前先记录 loadavg/swap，任何一项不满足就直接放弃，不产出"候选证据"。

## 二、输入源可以自动切换（省去手动）

实测（2026-10-22 补测）：**自动切回 ABC 可用，自动切入第三方开发源不可用**。
`TISSelectInputSource(<dev>.default)` 返回 0 且本进程内 `current` 立即变成开发源，但 1–3 秒后系统 `current` 仍是 ABC；
直接选父源（不带 `.default`）返回 **-50**。因此「进入开发源」仍需用户手动一次，自动化只能负责还原。

可用的部分（仓库自带探针）：

```sh
tools/macos-probe/bin/selsrc <input-source-id>   # 打印 select <id> <rc> 与切换后的 current
tools/macos-probe/bin/selsrc                    # 无参数只读（本机实测会崩溃，改用 dev-state）
```

本轮用 `selsrc com.apple.keylayout.ABC` 自动切回 ABC（`select … 0`，随后 `dev-state` 确认 `current=com.apple.keylayout.ABC`），
并据此完成了宿主精确退出与收尾；`acceptance-143/98-cleanup.txt` 记录四份 SHA。

### 自动切换的边界（仍然适用）

- 只能**切回 ABC**（及 Apple 自带布局）；切入第三方输入法在系统层面不生效（返回 0 但 current 不变），首次添加/移除也仍需手工。
- 进入开发源必须由用户手动；还原 ABC 由脚本完成，且**必须**回读确认、绝不改 `com.apple.HIToolbox`。
- 不在用户正在输入时切换；切换紧跟自有夹具的逐键守卫运行，失焦/源不符立即停止。
- 不自动注销/重启。

## 三、结论

- B 项（30MB）**仍待低压力窗口**；协议与前置条件已固定，下次可自动切源、无人值守完成一轮。
- 自动化只减少「切回」的手动步骤；进入开发源仍需用户一次操作，任何门禁都不因此放宽：16ms/30MB 仍以数据判定。
