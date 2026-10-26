# 209 air 侧 0.1.14/build 23 装机：已换包，GUI 验收被锁屏挡住

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

## 2. 卡在哪：air 的屏幕是锁着的

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
