# 264 · P1-U（ADR-324…336）装机与真机复验

- 日期：2026-11-12 / Claude Code（air 本机，Claude 桌面应用会话）
- 范围：把已合入 `main` 的 P1-U 三批改动（PR #269 / #270 / #271）装到 air，并做真机键入复验
- 结论：**装机 PASS；真机键入复验 22/22 PASS**（首轮因进程无「辅助功能 / 事件投递」权限 BLOCKED，用户授权后复跑通过，§3.1）。
  探针覆盖不到、仍需人工目视的 5 类项见 §5——**这些尚未验证**。

## 1. 候选身份

| 项 | 值 |
|---|---|
| 源码提交 | `3e428b78f69c4da525d131c66603fdc307b187a3`（`main`，Merge PR #271） |
| CI 构建 | `macOS Acceptance Package` run `43163118879`（success） |
| ZIP | `Lampyris-1.2.1-universal.zip`，SHA-256 `8e7aece75dd65de169de5b1b3417a6238e61a1ae817a61822edfe29e413f704b`（与随包 `.sha256` 一致） |
| 包内执行 SHA | `f38e4e1a238e38249de5f8b195454bc6e48e4da37272b879b58b6b57971ee82f` |
| 版本 / 构建号 | 1.2.1 / 40（**与线上发布版同号，内容不同**；发版前须升版本号） |
| 签名 / 公证 | `codesign --verify --deep --strict` 通过；`spctl`：accepted，Notarized Developer ID（2N62934Y28） |

## 2. 装机（PASS）

| 步骤 | 结果 | 证据 |
|---|---|---|
| 装前记录 | 已装 1.2.1/40，执行 `3eeeb0aa…`（`168115e`）；config `88651507…`；词库 1713 行 `bffc9d1a…`；`practice.tsv` `90530ef7…` | `00-pre.txt` |
| 用户数据备份 | config / 词库 / 练习进度复制到证据目录 | `userdata-before/` |
| 安装器预检 | `--dry-run`：签名与公证通过，但**拒绝在宿主运行时替换** | — |
| 停宿主并安装 | 切到 ABC → `pkill -x Lampyris` → `LAMPYRIS_RESTART_HOST=1 ./scripts/install.sh --app ./Lampyris.app`；旧包备份到 `updates/install-backup-20261112T060612Z/`；更新程序一并安装；尾部输出「已注册到输入源」 | `10-install.txt` |
| 装后回读 | 已装执行 SHA = 包内 `f38e4e1a…`；`SOURCE-COMMIT` = `3e428b7`；输入源已启用并选中；宿主 PID 23732，`lsof` 无 deleted inode（跑的是新二进制）；**config / 词库 / 练习进度 SHA 与装前逐一相同** | `11-post-install.txt` |

## 3. 真机键入复验（首轮 BLOCKED → 授权后 PASS）

### 3.0 首轮：BLOCKED

- `tools/macos-probe/quality-samples.sh` 在第一步「归位到中文态」即停，**没有执行任何用例**（`20-quality.txt`）。
- 归因：单独做一次最小键入（新建 TextEdit 文档 → `keytopid … 'wq ' --hid`）显示「posted」，但文档为空、`axtext` 报 `NO_WINDOW`。
  自检程序给出 `AXIsProcessTrusted() = false`、`CGPreflightPostEventAccess() = false`：**调用方进程未被系统信任**，
  合成按键被静默丢弃、AX 也读不到窗口。此前的验收都是从已授权的终端发起的。
- 这是系统安全设置，代理不应也没有去改；未向任何应用送达按键（权限不足时系统丢弃事件），未改动用户配置与词库。
- 探针自开的 2 个空白 TextEdit 文档已关闭、TextEdit 已退出（`99-restore.txt`）。

**工具缺陷（已修）**：`acceptance-preflight.sh` 此前在这种环境下仍报 `ready:true`，随后的键入项只会表现成含义不明的 BLOCKED。
现在 `keytopid --check-access` 提供只读自检，preflight 新增 `event_access` 检查，无权限时直接给出「请在已授权的终端里运行」并以 78 退出。

### 3.1 授权后复跑：22/22 PASS

用户在「系统设置 → 隐私与安全性 → 辅助功能」里为本会话的责任进程授权
（`~/Library/Application Support/Claude/claude-code/<版本>/…/claude.app`——桌面版 Claude 通过 `disclaimer` 助手把 TCC 责任转给它，
给 `/Applications/Claude.app` 授权无效；路径带版本号，Claude Code 更新后需重新授权）。
`keytopid --check-access` 回读 `ax_trusted:true, post_event:true`，preflight `event_access: ok`。

| 样本 | 结果 | 实得 |
|---|---|---|
| 五笔四码自动上屏 / 一级简码 | PASS | 你 / 的 |
| 混输拼音兜底、全拼双字词、拼音长词 | PASS | 你好 / 中国 / 中华人民共和国 |
| 中文标点句号、逗号、成对引号 | PASS | 你好。 / 你好， / ‘’ |
| 翻页键不破坏输入、撤销回到空态、长文本不丢字 | PASS | — |
| **数字后句点保持半角**（ADR-325） | PASS | `3.14` |
| **数字后逗号仍是中文**（ADR-325） | PASS | `3，` |
| **拼音没打完给补全**（ADR-326） | PASS | 你好 |
| **以词定字取首字 / 末字**（ADR-327） | PASS | 你 / 好 |
| **分段选词后回车**（ADR-330） | PASS | 你好shijie |
| **双拼（小鹤）**（ADR-336） | PASS | 你好 |
| **薄弱字清单**（ADR-335） | PASS | 「装」已记入 `weak-chars.tsv` |
| **按应用记住英文状态**（ADR-333） | PASS | nihao |
| 切输入源不丢字、失焦再回来不丢字 | PASS | abc \| 你好 / 你好 |

证据：`21-quality.txt`、`21-quality.stderr`、`quality-2/`、`99-restore-2.txt`。

**跑完后的状态（如实记录，不是全都原样）**：

| 项 | 状态 |
|---|---|
| 输入源 / 宿主 / 已装执行 SHA | 萤火虫已选中；宿主 PID 未变；执行 `f38e4e1a…` |
| `config.toml` | **取值已还原**（`mode=mixed`、`pinyin.scheme=full`、`practice.collect_weak_chars=false`），但文件里**多了这两行显式写出的默认值**，SHA 由 `88651507…` 变为 `52af2b90…`。按铁律 3 没有用备份文件覆盖回去 |
| `weak-chars.tsv` | 用例产生的文件已删除（装前不存在） |
| 用户词库 | 1713 → 1715 行。样本造成的：`nihao 你好`、`zhongguo 中国`、`zhonghuarenmingongheguo 中华人民共和国`、`r 的`、`wq 你` 学习次数增加，**新增一行 `pinyin zhuang 装 1`**（薄弱字用例的副作用，未清理）；其余变化是用户在此期间自己打字产生的 |
| `practice.tsv` | 未变 |
| TextEdit | 样本结束后仍在运行（无文档），已确认 0 个文档后退出 |

**样本自身的两个待改进点**：薄弱字用例会在用户词库留下一条学习记录；改配置后 `config.toml` 会多出显式默认值行。
两者都无功能影响，后续可让键入类样本统一跑在私有数据根（`LAMPYRIS_SUPPORT_DIR`，ADR-215）下根治。

## 4. 复跑方法

```sh
cd ~/Documents/EasyInputMethod
OUT="$PWD/platforms/macos/build/acceptance-air-p1u-3e428b7/quality" ./tools/macos-probe/quality-samples.sh
```

需在有辅助功能权限的进程里运行（已授权的终端，或已授权的代理会话）。约 4–5 分钟，期间会打开文本编辑并发送按键，请勿操作键盘。新增的 9 条样本（ADR-325…336）：

| 样本 | 按键 | 期望 |
|---|---|---|
| 数字后句点保持半角 | `3.14` | `3.14` |
| 数字后逗号仍是中文 | `3,` | `3，` |
| 拼音没打完给补全 | `nih␣` | `你好` |
| 以词定字取首字 / 末字 | `nihao[` / `nihao]` | `你` / `好` |
| 分段选词后回车 | `nihaoshijie2⏎` | `你好shijie` |
| 双拼（小鹤） | 拼音模式 + `pinyin.scheme=xiaohe`，`nihc␣` | `你好` |
| 薄弱字清单 | 开 `practice.collect_weak_chars`，`zhuang␣` | 上屏的字出现在 `weak-chars.tsv` |
| 按应用记住英文状态 | Shift 切英文 → 新建文档 → `nihao` | `nihao` |

样本会临时改配置（经 `ime-cli :set`，即 `ime-config` 的写路径）并在结束时还原；薄弱字用例产生的文件会删除；
「分段选词」会给用户词库里「你好」的拼音学习次数加一。

## 5. 仍需人工目视的项（探针覆盖不到）

| 项 | 原因 |
|---|---|
| `;` 选第二候选、`12:30` | 探针按键串以分号分段，打不出字面的 `;` 与 `:`；仅单测覆盖 |
| 拼音上屏后的五笔码浮层（ADR-331） | 浮层不在 AX 树里，需目视 |
| 练习窗口「字根」「词组」题型与错题加权（ADR-328/332/334） | 需目视；词组题答后讲解区（两位键码的格子）尚无截图 |
| 设置页 7 个新开关 | 同源代码已由 `test-settings-presentation.py` 覆盖，实机未看 |
| 安装完成页的上手提示（ADR-329） | 在 DMG 图形安装器里；本次用的是 ZIP + `install.sh` |

## 6. 回滚

旧包在 `~/Library/Application Support/Lampyris/updates/install-backup-20261112T060612Z/Lampyris.app`（1.2.1 发布版，执行 `3eeeb0aa…`）；
用户数据备份在证据目录 `userdata-before/`。

## 7. 证据

`platforms/macos/build/acceptance-air-p1u-3e428b7/`（不入库）：`00-pre.txt`、`10-install.txt`、`11-post-install.txt`、
`20-quality.txt`、`20-quality.stderr`、`99-restore.txt`、`userdata-before/`、`artifact/`、`extracted/`。
