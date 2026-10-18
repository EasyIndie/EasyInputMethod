# 077 — 不注销也能验收的三档方案 + 一条命令全新安装

2026-10-18。用户提出「设备上还跑着别的工作，频繁重启会打乱节奏，有没有不用手动重启的验收方案」。本轮把三档验收写进工作流，并补了一条命令的全新安装；**未在 A/B 上换包**。

## 三档（写进 `docs/开发工作流.md` §3）

| 档位 | 命令 | 能看到什么 | 代价 |
|---|---|---|---|
| ① UI 快照 | `make macos-ui-snapshots` | 候选窗 4 形态（单页/翻页/长词/附行）× 亮暗、关于、设置**四分区**、诊断；终端同时打印帧/留白/**快捷键文本** | 秒级，不显示窗口、不碰真实配置 |
| ② 隔离实窗 | `make macos-dev` | 同一 `CandidateWindow`/`SettingsPanel`/正式菜单组件 + 真实 Rust 会话 + **私有配置**，因此能看到默认绑定与候选行为 | 一个自建窗口，关掉即清理 |
| ③ 已装包 | `make macos-clean-install APP=<bundle>` | 真正的 IMK 链路（marked text、真实客户端焦点、系统菜单） | **一次注销** |

结论：①② 覆盖 UI、候选、设置、默认绑定与大部分交互，全程不注销、不碰安装目录；只有要证明「签名包在真机上的行为」才需要第 ③ 档，而**每次换包只需一次注销**（守则 2 的原因：热替换正在运行的输入法 bundle 会让源/菜单间歇失效，只能重登恢复）。

## 本轮新增

1. **设置面板按分区截图**：`settings-<theme>-<input|candidates|shortcuts|dictionary>.png`，快捷键页可直接看默认绑定；并打印一行客观文本（避免靠肉眼看小字）：

   ```
   ↳ 快捷键显示：toggle_mode=⌥M toggle_english=⇧ toggle_width=⌥空格 toggle_punctuation=⌥P
                  toggle_variant=⌥T open_settings=⌥, open_about=⌥A toggle_wubi_learning=⌥L
   ```
2. **`scripts/clean-install.sh` / `make macos-clean-install`**：登录后一条命令完成
   卸载旧包（默认带 `--purge-data`）→ 安装新包 → 校验 `codesign`/`stapler`/`spctl` → 打印执行 SHA →
   尝试自动选中输入源 → 报告配置是否已按默认值生成。
   - 不带 `--input-source-removed` 时**只打印注销前的两步清单并退出 2**，不猜、不动手。
   - `--dry-run` 可在当前登录直接预检（不会碰安装目录），已验证：

     ```
     ▶ 1/3 卸载旧包（含清理旧配置与词库）
     将把 …/Lampyris.app 移到 …/uninstalled/bundle.XXXXXX/
     将把用户数据移到 …/uninstalled/data.XXXXXX/：config.toml user-dictionary.tsv
     ▶ 2/3 安装新包
     （预检提示：当前已装其它版本，正式执行时第 1 步会先移走它）
     ▶ 3/3 校验已安装产物
     （预检结束，未改动安装目录）
     ```
   - `ARGS=--keep-data` 保留旧配置与词库（只想换包、不想重置时用）。

## 待执行的第 ③ 档（攒到方便时）

新包已就位并核验：源码 `6494eab`、zip SHA `0325ef9d…`、执行 SHA `8984c223…`、Notarized Developer ID。
注销重登后一条命令：

```sh
make macos-clean-install APP=packaging/out/clean-install/candidate-80z8RZ/extracted/Lampyris-0.1.0-universal/Lampyris.app
# 等价：scripts/clean-install.sh --app <路径> --input-source-removed
```

随后按报告 071 的探针流程核对默认行为（菜单右侧 `⌥M`/`⇧`/`⌥空格`/`⌥T`/`⌥P`/`⌥,`/`⌥A`、`wq`→你、`nihao`→你好、四状态、模式循环、设置/关于），结果另写报告。

## 验证

- `make macos-ui-snapshots UI=panels` 输出 8 张分区截图 + 快捷键文本行（见上）。
- `scripts/clean-install.sh --dry-run` 与「缺 `--input-source-removed`」两条路径实跑通过（后者退出 2 并打印清单）。
- `make verify` 全绿。
- 未改动已安装包与真实配置（`config.toml` SHA 仍 `907998e6…`）。

## 边界

- 第 ③ 档的一次注销仍必须由用户执行；脚本不自动注销、不在宿主运行时替换 bundle。
- 隔离实窗（第 ② 档）不是验收证据：它使用私有配置与独立进程，不能替代「同包 + 真实 IMK」结论。
