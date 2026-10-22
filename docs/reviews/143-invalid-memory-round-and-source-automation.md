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

实测：对**已启用**的输入源，`TISSelectInputSource` 可用。仓库自带的探针即可完成：

```sh
tools/macos-probe/bin/selsrc <input-source-id>   # 打印 select <id> <rc> 与切换后的 current
tools/macos-probe/bin/selsrc                    # 无参数只读（本机实测会崩溃，改用 dev-state）
```

本轮用 `selsrc com.apple.keylayout.ABC` 自动切回 ABC（`select … 0`，随后 `dev-state` 确认 `current=com.apple.keylayout.ABC`），
并据此完成了宿主精确退出与收尾；`acceptance-143/98-cleanup.txt` 记录四份 SHA。

### 自动切换的边界（仍然适用）

- 只能选**已经启用**的源；首次添加/移除第三方输入法仍需用户在系统设置里操作（TISEnable/Disable 返回 0 但不生效）。
- 只在自有固定开发身份与 ABC 之间切换，且**必须**：切换后回读当前源确认、采样结束切回 ABC、绝不改 `com.apple.HIToolbox`。
- 不在用户正在输入时切换；切换紧跟自有夹具的逐键守卫运行，失焦/源不符立即停止。
- 不自动注销/重启。

## 三、结论

- B 项（30MB）**仍待低压力窗口**；协议与前置条件已固定，下次可自动切源、无人值守完成一轮。
- 自动化只减少手动步骤，不放宽任何门禁：16ms/30MB 仍以数据判定。
