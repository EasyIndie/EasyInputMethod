# 报告 302：1.3.1 / build 44 候选验收

日期：2026-11-18 / pi（air）· 候选提交 `677e046`

## 1. 候选身份

| 项 | 值 |
|---|---|
| 提交 | `677e046d9c9afe85f880e035680d8e9dbcd041b4` |
| 版本 / 构建 | 1.3.1 / 44 |
| 验收产物 run | `macOS Acceptance Package`（main push） |
| ZIP | `0fbe7ff3c73a2a76384914a5021ac129abab796583a0090ae50c5113f7a2e41a`（与 `.sha256` 一致） |
| 包内宿主执行 SHA-256 | `68f892c501a4f0b3031ccce0afe4aa75a50e239bcaecffc42bbc2f1fda12f370` |
| 签名 / 公证 | `spctl` accepted，`source=Notarized Developer ID`，团队 `2N62934Y28` |
| 架构 | universal（arm64 + x86_64） |

## 2. 装机

- 用仓库 `platforms/macos/install.sh` 覆盖安装（旧包备份 `~/Library/Application Support/Lampyris/updates/install-backup-20261118T103027Z/`），
  安装器回读「已注册到输入源」，输入源保持 `cn.jokerhub.inputmethod.Lampyris.default` 并选中。
- 装机前后：config `52af2b90…` 未变、词库 2391 行未变。
- 已装执行 SHA = 包内执行 SHA（上面那行），版本回读 1.3.1 / 44。

## 3. 真机自动验收

| 项 | 结果 | 证据 |
|---|---|---|
| 质量样本 `quality-samples.sh`（隔离数据根） | **30/30 PASS，0 blocked** | `quality-samples-20261118T103036Z.log` |
| 状态热键 `acceptance-auto.sh` | 8/8 PASS（Shift 中英、⌥P 标点、⌥F 全角、⌥T 繁简、⌥M 模式、还原） | `acceptance-auto-*.log` |
| 性能 | 稳态 p50 3.3–5.4 ms、逐轮 p95 5.1–8.6 ms；冷首键 p95 25.54 ms（ADR-307 单独披露） | 同上 |
| 零外联 | `net.csv` 501 个采样点全部为 0 | `net.csv` |
| 内存门禁（ADR-338 口径） | **PASS**，限 24 MiB，3 轮稳态 | `memory-gate-*.log` |

## 4. 沿用的真机人工结论

本候选相对已验收的 `14739f6`（执行 `66d57e19…`）**只差版本号与构建号**，代码逐字节相同（CI 报告
`去签名可执行文件逐字节一致` 只在同一 SDK 下成立，此处以 diff 只涉 `Cargo.toml`/`build-number` 为据）。
`14739f6` 上用户已验收的 8 项行为（浮层、标点、窗口落点、练习重试、字根标注、口/囗 辨识、打满即判分、空格确认、
判对不自动走、达标横幅、未达标提示）继续有效，不再重复换包走查。

## 5. 发版动作

见 `docs/releases/1.3.1.md`：tag `v1.3.1` → Release（ZIP/DMG/更新程序/appcast）→ 站点 Pages → pro 升级。
