# 264 · P1-U（ADR-324…336）装机与真机复验

- 日期：2026-11-12 / Claude Code（air 本机，Claude 桌面应用会话）
- 范围：把已合入 `main` 的 P1-U 三批改动（PR #269 / #270 / #271）装到 air，并做真机键入复验
- 结论：**装机 PASS；真机键入复验 BLOCKED**——本会话的进程没有「辅助功能 / 事件投递」权限，按键被系统静默丢弃，
  **12 项行为在真机上一项都还没验证**。需要在已授权的终端（如 ghostty）里跑一条命令补做（§4）。

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

## 3. 真机键入复验（BLOCKED）

- `tools/macos-probe/quality-samples.sh` 在第一步「归位到中文态」即停，**没有执行任何用例**（`20-quality.txt`）。
- 归因：单独做一次最小键入（新建 TextEdit 文档 → `keytopid … 'wq ' --hid`）显示「posted」，但文档为空、`axtext` 报 `NO_WINDOW`。
  自检程序给出 `AXIsProcessTrusted() = false`、`CGPreflightPostEventAccess() = false`：**调用方进程未被系统信任**，
  合成按键被静默丢弃、AX 也读不到窗口。此前的验收都是从已授权的终端发起的。
- 这是系统安全设置，代理不应也没有去改；未向任何应用送达按键（权限不足时系统丢弃事件），未改动用户配置与词库。
- 探针自开的 2 个空白 TextEdit 文档已关闭、TextEdit 已退出（`99-restore.txt`）。

**工具缺陷（已修）**：`acceptance-preflight.sh` 此前在这种环境下仍报 `ready:true`，随后的键入项只会表现成含义不明的 BLOCKED。
现在 `keytopid --check-access` 提供只读自检，preflight 新增 `event_access` 检查，无权限时直接给出「请在已授权的终端里运行」并以 78 退出。

## 4. 补做方法（需用户在已授权的终端里执行）

```sh
cd ~/Documents/EasyInputMethod
OUT="$PWD/platforms/macos/build/acceptance-air-p1u-3e428b7/quality" ./tools/macos-probe/quality-samples.sh
```

约 4–5 分钟，期间会打开文本编辑并发送按键，请勿操作键盘。新增的 9 条样本（ADR-325…336）：

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
