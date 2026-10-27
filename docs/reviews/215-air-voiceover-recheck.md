# 215 air + VoiceOver 复测：0.1.16 上不可复现

> 对象：报告 [210](210-air-sleep-space-voiceover.md) §3.1 记录的「air 开启 VoiceOver 后，装机版输入上下文掉回 ABC，
> `wq,` 打出裸 `wq`，输入法菜单显示「正在加载…」」。该结论一直作为未定位缺陷挂在发布清单上。
> 本次在 **0.1.16 / build 26**（宿主执行 `743fb3c8…`，更新程序 0.1.16/26）上按更苛刻的条件复测。

## 1. 结论

**不可复现**。两种顺序都正常，且第二次刻意复刻了报告 210 的现场条件（VoiceOver 先开着，宿主随后才启动）。

| 条件 | 操作 | 结果 | 证据 |
|---|---|---|---|
| A：宿主先跑，后开 VO | VO 21:54:16 启动，用户在 TextEdit 输入 | 9 秒后宿主日志出现 `Setting marked text`、`Menu` 与 `CandidatePanel` 建窗 → 正常组字 | `ev-32-vo-attempt1.txt` |
| B：**VO 先开，宿主后启动**（报告 210 的现场） | VO 保持开启（PID 31461）→ 停掉宿主 23396 → 用户敲 `wq`，IMK 重新拉起宿主 **PID 31627** | `Activate Server` → `Menu` → `Setting marked text`；**用户实测打出「你」且有候选窗** | `ev-33/34/35` |

补充观察（12 分钟内）：宿主 IMK 调用 1806 次，`current` 始终为 `cn.jokerhub.inputmethod.Lampyris.default`，未回退 ABC；期间没有一次属于本产品的 `IMKServer` 超时或连接被拒。

## 2. 顺手排掉的日志噪音

日志里反复出现

```
imklaunchagent[737] [com.apple.inputmethodkit:Server] Refusing connection name for bundle:
unrecognized 'InputMethodConnectionName' value
```

一开始像是本产品的连接名有问题。核对两处输入法目录后确认**与本产品无关**：

| bundle | `InputMethodConnectionName` | 与 `CFBundleIdentifier + "_Connection"` 一致性 |
|---|---|---|
| `~/Library/Input Methods/Lampyris.app` | `cn.jokerhub.inputmethod.Lampyris_Connection` | ✅ 一致 |
| `/Library/Input Methods/SogouInput.app`（搜狗） | `Sogou_InputMethod_Connection` | ❌ 应为 `SogouInput_Connection` |

也就是说这条 `Refusing connection name` 是第三方输入法的连接名不合规造成的周期噪音。以后再看到它，先按上面的方法核对各 bundle，别当成自己的问题。

## 3. 与报告 210 的差异怎么解释

- 报告 210 的观察发生在 **build 23**，且当时 air 刚经历「装包 → 卸载 → 注销 → 重装」的一轮折腾（报告 209/210 记录的输入源反复增删）。
- 从 build 23 到 26，宿主侧只有一处改动：ADR-294 的更新程序定位（`InputMenu.swift`），不涉及输入上下文、AX 或 IMK 连接生命周期。
- 因此更可能的解释是：报告 210 那次是**输入源/IMK 会话处于异常状态**（重装后 TSMDocument 与输入源注册未稳定）时的偶发现象，而不是「VoiceOver 与本产品冲突」的稳定缺陷。

## 4. 处置

- 报告 210 §3.1 的结论**降级**为「build 23 上的一次不可复现观察」，不再作为 air 的已知限制挂在发布清单上。
- 保留监测：若在 0.1.16 及以后版本再次出现，按本文 §1 的条件 A/B 复现并抓 `imklaunchagent` + 宿主 IMK 日志。
- 反例条件（写进 IT-22 走查）：**VoiceOver 开启 → 宿主重启 → 立即打字**，三条一起做才算覆盖。

## 5. 证据

`platforms/macos/build/acceptance-air-e54a0c3/`（不入库）：`ev-30-vo-state.txt`（VO 与宿主进程/输入源）、`ev-31-vo-log.txt`（IMK 事件）、`ev-32`/`ev-33`/`ev-34`/`ev-35`（两次复现的条件与结果）。
