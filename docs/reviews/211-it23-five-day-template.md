# 211 IT-23 五工作日试用记录（v0.1.14）

> 用途：给**用户本人**（ADR-125：一位试用者即满足人数）在 **1.0.0 / build 29**（锁定候选，报告217）上做累计 5 个工作日的日常试用，逐日留证。
> 这不是工程自测，代理签字的记录不算；本文件由用户填写，代理只负责整理与最后补进 schema 2 报告。
> 门禁要求见 `docs/MVP产品验收标准.md` 与 `docs/MVP单人验收清单.md` §「五工作日观察记录」。

## 0. 试用对象（已固定，勿改）

| 项 | 值 |
|---|---|
| 版本 / 构建 | **1.0.0 / build 29** |
| 源码提交 | `11abece3a348213429441950af667235486a482d`（锁定候选，报告217） |
| 执行文件 SHA-256 | `4ad949e6c3608c689c07e8a3f092a53babc788b290e424b4784bebc1d3aae31c` |
| 候选资产 | ZIP `aca4ed5c…`（= 候选，逐字节）、源码 `40d88f36…`；Release 资产待发布后对账 |
| 签名 | Developer ID + 公证（`spctl` = `accepted source=Notarized Developer ID`） |
| 设备 | air（arm64 / macOS 27.0.1）与 pro（Intel / macOS 13.7.8）**执行 SHA 相同**，均为 `4ad949e6…` |

> 每天开始前花 5 秒确认：`shasum -a 256 "$HOME/Library/Input Methods/Lampyris.app/Contents/MacOS/Lampyris"` 应为上面那个 SHA。
> 如果哪天换了包（哪怕只是 build 变了），**当天记录作废重来**，否则 5 天不在同一个候选上。

## 1. 每日记录表

每天至少覆盖：**中英混排、较长输入、撤销、焦点切换、睡眠唤醒**这五类场景。发现丢字/错字/崩溃按“严重问题先修再复验”，不能靠“多数时候正常”关闭。

| 日期 | 设备/系统 | 场景（五类必填 + 其他） | 结果 | 现象/复现步骤 | 恢复方式 | 证据 |
|---|---|---|---|---|---|---|
| 第 1 天 | | 混排 / 长输入 / 撤销 / 焦点切换 / 睡眠唤醒 | PASS / FAIL / BLOCKED | | | |
| 第 2 天 | | 同上 | | | | |
| 第 3 天 | | 同上 | | | | |
| 第 4 天 | | 同上 | | | | |
| 第 5 天 | | 同上 | | | | |

填写口径：

- **结果**只写 `PASS` / `FAIL` / `BLOCKED` / `SKIP`，不写“基本正常”。
- **现象**：写下按键序列与看到的文本（例：`想打「你好」打了 nihao 第 3 次出现「拟好」`），不填个人隐私内容。
- **证据**：能指到文件就写路径（截图、复制的候选窗截图、`/tmp/...` 日志都行）。
- 遇到问题当天记录；修复后**在新包上重跑受影响的那一天**，不要用旧包补记。

## 2. 已知限制（不是本次试用要修的东西）

| 限制 | 说明 |
|---|---|
| 浏览器地址栏预编辑残留（UX-1） | Chrome/Safari 地址栏组合中切走会留下原始编码字母（如 `nihao`），`Esc` 取消即可；原因在 macOS IMK 回调时机，已接受 |
| air 上开启 VoiceOver 时输入上下文掉回 ABC | 报告210 §3.1，未定位；关掉 VoiceOver 恢复 |
| `install.sh` 的“已自动注册”措辞 | 本版发布包内仍是旧脚本（修复在 `v0.1.14` 之后入库），需要手动在系统设置添加输入源 |
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
