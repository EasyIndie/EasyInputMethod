# 209 air 侧 0.1.14/build 23：装包、自动验收、内存口径对照（GUI 人工项待补）

## 1. 做了什么

air（`ssh air`，arm64 / macOS 27.0.1 / SDK 27.0 / Swift 6.4）此前是 **0.1.13 / build 21**（执行 `c3b533e4…`），现在换成候选包：

| 项 | 值 |
|---|---|
| 来源 | `Lampyris-0.1.14-universal.zip`（`shasum -c` 对照资产 `.sha256` → OK） |
| 解压后执行 SHA | `a165f05c0b704796380a39f5666da5e2cfa1a8cb2d23868dfd3d1532d429e4dc`（= pro 上的同一包） |
| 校验 | `codesign --verify --strict --deep` PASS；`spctl` = `accepted source=Notarized Developer ID` |
| 换包方式 | 原地换包（同 ADR-230 做法）：停宿主 → 旧 bundle 移入 `uninstalled/bundle.VQzkTh` → 复制新 bundle → 校验 → 启动 |
| 装后状态 | 执行 SHA `a165f05c…`、build 23、宿主 PID 75610 正常运行、无崩溃报告、`config` 仍 `809e2cae…`、词库 646 行（学习写入） |

在 macOS 27 / arm64 上宿主能正常加载，是这次唯一拿到的结论。

## 2. 当时卡在哪：air 的屏幕是锁着的（已解锁，见 §5）

探针（`/tmp/locksess`，读 `CGSessionCopyCurrentDictionary`）：

```
CGSSessionScreenIsLocked = 1
kCGSSessionOnConsoleKey  = 1
kCGSSessionUserNameKey   = joker
```

后果（都实测过）：

- `type-session.sh` → `BLOCKED 测试窗口未取得前台（激活键未投递）`；
- `osascript ... set frontmost` 无效，前台仍是 ChatGPT；
- 测试窗口 `axwins` 查不到窗口。

所以 air 侧的键入、热键、质量样本、VoiceOver、睡眠唤醒、多 Space **全部没跑**，`acceptance-preflight` 也只到「宿主未运行」为止（现已手动拉起宿主）。

## 3. 解锁后要跑什么（一次跑完，约 25 分钟）

```sh
cd ~/Documents/EasyInputMethod
make macos-probe-build
./tools/macos-probe/bin/tissrc select cn.jokerhub.inputmethod.Lampyris.default   # 可能需要手动在菜单里点一次
make macos-auto-acceptance                 # 热键/上屏 + 客户端矩阵 + 性能/零外联
./tools/macos-probe/quality-samples.sh     # 16 项（脚本会先拒多实例 TextEdit）
./tools/macos-probe/memory-gate.sh         # ADR-263，会重启宿主
```

人工项（需要人在 air 前面）：

1. **VoiceOver 复听**：`wq` → → → 空格，听「第2项，像，五笔」「像，已上屏」（pro 上已通过，air 是 macOS 27 + arm64，属新环境）；
2. **睡眠→唤醒**：`./tools/macos-probe/sleep-test.py`（会真的睡眠）；
3. **多 Space**：手动切桌面后按报告 205 §2 判候选窗落点。
4. 注意 air 上还启用了**搜狗**输入源，per-app 输入源记忆可能让新开的 App 用错源；验收前先确认当前源是萤火虫。

## 4. 回滚

- 0.1.13：`~/Library/Application Support/Lampyris/uninstalled/bundle.VQzkTh`（换包前的原包，执行 `c3b533e4…`）；Release 的 ZIP/DMG 也在。
- 回滚步骤：停宿主 → `mv` 回 `~/Library/Input Methods/Lampyris.app` → 校验执行 SHA。

## 5. 结论

- air 已是 build 23，但**没有 GUI 结论**，因此「两设备一致」目前仍不成立：pro 有完整证据（报告207），air 只有「能启动、不崩」。
- 在 air 解锁并跑完 §3 之前，不应宣布 0.1.14 双设备就绪，更不应据此打 tag。

## 5. 解锁后的验收结果（2026-10-26 20:40 起，SSH 驱动，macOS 27.0.1 / arm64）

| 项 | 结果 |
|---|---|
| preflight | `ready: true`，`exec_sha = a165f05c…`（与 pro 同一包） |
| `make macos-auto-acceptance` | **PASS**：混输+标点 `你你好。`、Shift 英/中、⌥P `。`、⌥F `１２12`、⌥T `學習`/`学习`、⌥M；**客户端 5/5**（TextEdit / Safari / Chrome / Ghostty / Xcode，air 装了 Xcode 27 所以比 pro 多一项）；p50 2.45ms、p95 7.71ms、max 13.53ms、**0 外联连接**（`/tmp/lampyris-acceptance-air-209c`） |
| `quality-samples.sh` | **16/16 PASS**（`/tmp/lampyris-quality-air-209`） |
| 播报（AX 取证） | `axobserve` 抓到 `AXAnnouncementRequested`（候选组，换候选）+ `AXSelectedChildrenChanged` + `AXAnnouncementRequested`（AXApplication，上屏），与 pro 完全同构（`/tmp/air-vo-events.json`） |
| `memory-gate.sh` | 见 §6（原判 FAIL → ADR-292 后 PASS） |
| 人工项 | **VoiceOver 人耳、睡眠唤醒、多 Space 仍需在 air 前面的人**（我只能在 AX 层取证） |

### 5.1 首轮客户端矩阵 FAIL 的两处根因（都是探针，不是产品）

1. **Safari**：文字确实上屏了（AX 里读到 `你你好。`），但 macOS 27 上页面标题不再随输入更新，而矩阵只读 `document.name` → 改为先用 `axtext` 读输入区（新增 AXTextField 回退，跳过 URL 栏），读不到才退回标题。
2. **TextEdit**：一次运行里 `axfocus` 报 `NO_FOCUS_PID`（和报告198/199 同类的时序），改为回退读前台窗口文本区。
   两处修完在 air 上重跑得 **5/5 PASS**。

## 6. 内存门禁在 macOS 27 上判 FAIL 的真因（ADR-292 的由来）

首次运行 `memory-gate.sh` → **FAIL**：稳态 footprint 29.3–32.4M（上限 30M）。做了**同机 A/B**：把 air 换回 0.1.13（`uninstalled/bundle.194538`，执行 `c3b533e4…`）重跑

| 版本 | footprint（稳态） | 私有已提交（Writable resident + swapped） |
|---|---|---|
| 0.1.13 | 29.4–33.8M | 25.7–28.9M |
| 0.1.14/build 23 | 29.3–32.4M | 25.7–28.0M |

两版几乎一样、0.1.13 甚至更高 → **不是回归**。`vmmap` 显示 `ReadOnly portion of Libraries: resident=164.7M`，即 footprint 里混了随 OS 增大的共享库页（同一份代码在 macOS 13 上 footprint 只有 20.6–20.9M）。
按 **ADR-292**（本次新增）：判定改用「私有已提交 ≤30MiB」，footprint 仍采样但标记为参考；跨 macOS 版本只做同 OS 内比较。改后 air 重跑 **PASS**（私有 25.7–28.0M）。

## 7. 仍未做（需要人在 air 前面）

1. **VoiceOver 人耳复听**（AX 层已证明播报发出，缺耳朵确认）；
2. **睡眠→唤醒**：`sleep-test.py` 会真的让机器睡下，需要有人唤醒（或授权我 `pmset schedule wake` 定时唤醒）；
3. **多 Space**：合成按键切不动 Space，需手动切一次再自动判落点。

## 8. 结论

- air 与 pro 现在跑**同一个包**（执行 `a165f05c…`），自动项在两边都绿；播报在两套 OS（13.7.8 x86_64 / 27.0.1 arm64）上都有 AX 级证据。
- 剩余人工项（VO 人耳、睡眠、Space）不影响「双设备自动项一致」的结论，但按 ADR-084 仍要在 air 上补完才能宣布双设备验收完成。
