# 211 IT-23 五工作日试用记录（1.0.0 / build 34）

> 用途：给**用户本人**（ADR-125：一位试用者即满足人数）在 **1.0.0 / build 34**（锁定候选，报告217）上做累计 5 个工作日的日常试用，逐日留证。
> 这不是工程自测，代理签字的记录不算；本文件由用户填写，代理只负责整理与最后补进 schema 2 报告。
> 门禁要求见 `docs/MVP产品验收标准.md` 与 `docs/MVP单人验收清单.md` §「五工作日观察记录」。

## 0. 试用对象（已固定，勿改）

| 项 | 值 |
|---|---|
| 版本 / 构建 | **1.0.0 / build 34** |
| 源码提交 | `27301f5ca98734205a7dbe0d60d6efa99d3593dc`（锁定候选，报告217 §8） |
| 执行文件 SHA-256 | `9439488404a16414d9f2af7ba92d7ee0a735cbbbf27566a7f437b28ac58c7c25` |
| 候选资产 | ZIP `a7f89ee19d08e323eb1a4e8f8c577c413fe60d6d14ab0b2966cb139bbb4795c0`（= 候选，逐字节）；Release 资产待发布后对账 |
| 签名 | Developer ID + 公证（`spctl` = `accepted source=Notarized Developer ID`） |
| 设备 | air（arm64 / macOS 27.0.1）与 pro（Intel / macOS 13.7.8）**执行 SHA 相同**，均为 `94394884…` |

> 每天开始前花 5 秒确认：`shasum -a 256 "$HOME/Library/Input Methods/Lampyris.app/Contents/MacOS/Lampyris"` 应为上面那个 SHA。
> 如果哪天换了包（哪怕只是 build 变了），**当天记录作废重来**，否则 5 天不在同一个候选上。

## 1. 每日记录表

每天至少覆盖：**中英混排、较长输入、撤销、焦点切换、睡眠唤醒**这五类场景。发现丢字/错字/崩溃按“严重问题先修再复验”，不能靠“多数时候正常”关闭。

| 日期 | 设备/系统 | 场景（五类必填 + 其他） | 结果 | 现象/复现步骤 | 恢复方式 | 证据 |
|---|---|---|---|---|---|---|
| 第 1 天 · 2026-10-30 | air / macOS 27.0.1 | 混排 / 长输入 / 撤销 / 焦点切换 / 睡眠唤醒 | **PASS** | 用户确认五类场景均正常，无丢字/错字/崩溃；取证回读宿主 `1.0.0/34` 执行 `94394884…`、PID 1595、`updates` 备份在、输入源 `Lampyris.default` 在用、config `4e9ff396…`、词库 893 行 | — | `platforms/macos/build/acceptance-air-1.0.0-b34/evidence/it23-day1-20261030T031257Z.txt` |
| 第 2 天 · 2026-10-31（周六） | air / macOS 27.0.1 | 混排 / 长输入 / 撤销 / 焦点切换 / 睡眠唤醒 | **PASS** | 用户确认通过；取证回读宿主仍为 `1.0.0/34` 执行 `94394884…`、PID 1595 未变（未换包）、config `4e9ff396…` 不变、词库 893 → **944 行**（正常学习增长） | — | `platforms/macos/build/acceptance-air-1.0.0-b34/evidence/it23-day2-20261031T100448Z.txt` |
| 第 3 天 | | 同上 | | | | |
| 第 4 天 | | 同上 | | | | |
| 第 5 天 | | 同上 | | | | |

**工作日口径（待你确认）**：门禁原文是「连续 5 个工作日」（`macos-release-checklist.md` IT-23）。
2026-10-31 是**周六**，若按严格工作日口径，这天应记为「附加观察」而不占 5 天名额，第 2 天顺延到 2026-11-02（周一）；
若你的使用节奏把周六算作工作日，则按上表直接计入。默认先按**计入**记录，等你一句话决定是否改判。

填写口径：

- **结果**只写 `PASS` / `FAIL` / `BLOCKED` / `SKIP`，不写“基本正常”。
- **现象**：写下按键序列与看到的文本（例：`想打「你好」打了 nihao 第 3 次出现「拟好」`），不填个人隐私内容。
- **证据**：能指到文件就写路径（截图、复制的候选窗截图、`/tmp/...` 日志都行）。
- 遇到问题当天记录；修复后**在新包上重跑受影响的那一天**，不要用旧包补记。

## 2. 已知限制（不是本次试用要修的东西）

| 限制 | 说明 |
|---|---|
| 组合中切到无候选的模式（ADR-302） | 候选窗会隐藏、编码以预编辑文本留在输入框，按 `Esc` 取消或继续补码 |
| 浏览器地址栏预编辑残留（UX-1） | Chrome/Safari 地址栏组合中切走会留下原始编码字母（如 `nihao`），`Esc` 取消即可；原因在 macOS IMK 回调时机，已接受 |
| 拼音质量 | 轻量兜底，不等同整句/长词（ADR-031） |

## 3. 结束后如何并入门禁

1. 把每天结论汇总进 schema 2 报告（`one-person-five-days` 用例，PASS 要附证据文件路径）：

   ```sh
   python3 platforms/macos/tests/acceptance-results.py template /tmp/lampyris-acceptance.json
   # 填 candidate.sha256 / commit / architectures / signature、environment、各用例
   python3 platforms/macos/tests/acceptance-results.py check /tmp/lampyris-acceptance.json
   ```

2. 本文件的表格补完后，作为该用例的证据之一（相对路径引用即可）。
3. 5 天里出现 FAIL 项：先修 → 出新包（build +1）→ **在新包上重跑受影响的场景**，并把这 5 天重置（同一候选的要求，见 §0）。
