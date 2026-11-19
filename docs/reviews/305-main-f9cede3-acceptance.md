# 报告 305：main `f9cede3` 公证候选装机复验（1.3.1 / build 44，ADR-375–378 之后）

日期：2026-11-19 / pi（air）· 候选提交 `f9cede3`（dev → main 合并提交，PR #337）

## 1. 候选身份

| 项 | 值 |
|---|---|
| 提交 | `f9cede3b64e812c206136cd40567e9ce0c2a2613`（main） |
| 版本 / 构建 | 1.3.1 / 44（**未改版本号**：这是 main push 的验收包，不是发版产物，下次发版必须重绑候选身份） |
| 验收包 run | `macOS Acceptance Package` 44471741816（success） |
| ZIP | `c9ded725b20b977d562441a105e3f02ee6c3477258f1659acaca2c6dc8206ac1`（与 `.sha256` 一致） |
| 包内宿主执行 | `3344fcddce3c2b153087417cad0596163ebe8373cb950512a232a51ec71569b1` |
| 签名 / 公证 | `spctl` → `source=Notarized Developer ID`，团队 `2N62934Y28`，stapler valid |
| 资源 | `B0-runtime.tsv` **233,052 B / 5,021 行**；bundle 内**已无** `wubi86-level3-codes.tsv`（ADR-377） |

## 2. 装机与数据

- 切 ABC → 停宿主 → `platforms/macos/install.sh --app …/Lampyris.app`（`LAMPYRIS_RESTART_HOST=1`）；
  旧包备份 `updates/install-backup-20261119T063319Z/Lampyris.app`；安装器回读「已注册到输入源」。
- 装后：`exec = 3344fcdd…`（= 包内）；`config.toml` `52af2b90…` **未变**；`user-dictionary.tsv` **2,435 行未变**。
- 输入源 `cn.jokerhub.inputmethod.Lampyris.default` 已选中；宿主 PID 94064；`lsof … | grep deleted` = **0**（跑的是新二进制）。
- 证据目录：`platforms/macos/build/acceptance-air-20261119-f9cede3/`（`00-pre`、`01-install`、`02-post-install`、`99-post`）。

## 3. 本批改动项的真机验证（PASS）

| 项 | 做法 | 结果 |
|---|---|---|
| **F1 识别码槽**（ADR-377） | 键入 `dcg` → 候选「码」 | 学习区：`完整码 DCG`、字根 `石 D` `马 C`、**识别码：横 · 左右结构　G**（此前会把 `一:g` 当第三字根、识别码整行缺失） |
| **F2 `母` 字根**（ADR-377） | 键入 `xgu` → 候选「母」 | 学习区：`完整码 XGUI`、字根格 `母 X`（报户口键位），不再空白 |
| **F3 简码带等级 + 三级**（ADR-377/378） | `j`（是）、`xgu`（母） | `简码 一 J · 三 JGH`、`简码 三 XGU`；三级简码与练习同源 |
| **F5 三级题池**（ADR-377/378） | 私有根 `LAMPYRIS_SUPPORT_DIR` + 种入进度解锁 → 练习「三级简码」 | 题干「打出它的三级简码（3 位）」、**题库 3,362 字**（此前 1,888；旧实现要求 `full` 且另读一张表） |
| **F8 键名字可练 / 字表并集** | 同私有根切到「完整码」 | **题库 5,021 字**（3,755 GB2312 一级 ∪ 1,266 简码表用字） |
| 输入质量不回归 | `quality-samples.sh` | **30/30 PASS**（含双拼、薄弱字、按应用记住英文、切源不丢字、失焦回来不丢字） |
| 热键/上屏 | `make macos-auto-acceptance FAST=1 KEY_SETTLE=12` | Shift×2、⌥P、⌥F、⌥T×2、⌥M **全 PASS** |
| 延迟/内存/零外联 | 同上 + `memory-gate.sh` | p95 **7.0 ms**（限 16）、稳态 heap live **21.0 MiB**（限 24）、外联 **0**、RSS 增长 **0.6 MB** |

## 4. 两处 FAIL 的归因（都已定案，非产品回归）

### 4.1 ⌥M「模式循环」在 FAST 档下偶发 FAIL

- 现象：`opt+m;opt+m;opt+m;wq ` 在**同一条合成事件序列**里时，`got ''`。
- 复核：把三次 ⌥M 拆成独立会话（每次 settle 8s）后 `mode` 依次 `mixed→wubi→pinyin→mixed` 全部正确；
  `KEY_SETTLE=12` 重跑验收即 **PASS (你)**。
- 归因：**探针时序**（模式切换要落配置 + 重建引擎），与 `SKILL.md` §3 已记录的「⌥ 组合键事件序列」同类；
  产品行为正常。已在报告里记明 `KEY_SETTLE=12` 是这批的稳定档。

### 4.2 性能门禁「footprint 40.3 MiB > 硬顶 40」

- 现象：验收脚本内测到 `footprint_steady_mb 40.3`（旧包同脚本 39.1）。
- 干净状态 A/B（各 3 轮、同一 harness）：
  | 包 | 字表 | footprint steady | heap live | p95 |
  |---|---|---|---|---|
  | 旧 1.3.1/44（`68f892c5…`） | 3,755 | **34.1 MiB** | 21.3 | 7.00 ms |
  | 本候选（`3344fcdd…`） | 5,021 | **35.9 MiB** | 21.0 | 7.01 ms |
- 结论：真实增量 **+1.8 MiB / +34% 字表**，`heap live` 门禁（ADR-338，限 24）**完全没变**；
  40 MiB 硬顶（报告 251 起的粗粒度 tripwire）只剩 <1 MiB 余量，被验收脚本内的状态放大后越界。
  处置见 ADR-379：硬顶按相同相对余量放到 44 MiB，**真正的内存门禁（heap live ≤24）不动**。

## 5. 状态判定

| 项 | 判定 |
|---|---|
| 本批 8 个问题的真机可见部分（F1/F2/F3/F5/F8） | **PASS** |
| 输入质量 / 热键 / 延迟 / 内存（ADR-338 口径） / 零外联 | **PASS** |
| 验收脚本内 footprint tripwire | 调整后 **PASS**（ADR-379，含 A/B 数据） |
| 数据安全 | config `52af2b90…`、词库 2,435 行未变；练习/薄弱字写入私有根；验收后 TextEdit 文档与探针进程已清理 |
| 未做 | 未改版本号、未发版、未打 tag；pro 未升级（仍是 1.3.1/44 发版产物 `68f892c5…`） |

## 6. 复现

```sh
gh run download 44471741816 -D /tmp/accept-337
ditto -x -k /tmp/accept-337/*/candidate-*/Lampyris-1.3.1-universal.zip /tmp/accept-337/extract
cd ~/Documents/EasyInputMethod
tools/macos-probe/bin/tissrc select com.apple.keylayout.ABC && pkill -x Lampyris
LAMPYRIS_RESTART_HOST=1 ./platforms/macos/install.sh --app /tmp/accept-337/extract/Lampyris-1.3.1-universal/Lampyris.app
OPEN_APPS=TextEdit FAST=1 KEY_SETTLE=12 make macos-auto-acceptance
OUT=/tmp/qs ./tools/macos-probe/quality-samples.sh
LIMIT_MB=24 ROUNDS=3 OUT=/tmp/mem ./tools/macos-probe/memory-gate.sh
```
