# 102 — IT-14 前置：CI 出「隔离身份 + Developer ID」包（A 机进行中）

2026-10-19，A（Intel / macOS 13.7.8）。目标：让 CI 产出**隔离身份 + Developer ID 签名/公证**的测试包，
用来补验报告 101 里 `application-Safari` / `application-Terminal` / 「已装独有包输入」的 BLOCKED 项。

**当前状态：出包与安装完成；系统发现卡在「需一次重新登录」，探针尚未执行。**
本报告先固定已完成部分与阻塞证据，重新登录后由后续会话续写结果（见 §5）。

## 1. 工具扩展（提交 `c60bd88`）

| 文件 | 改动 |
|---|---|
| `.github/workflows/isolated-imk-notary.yml` | 新增 `arch`（`arm64`/`x86_64`/`universal`）；固定 arm64 runner 上交叉构建（Rust `--target` + Swift `-target <arch>-apple-macosx13.0` + `lipo`）；签名前用 `lipo`/PlistBuddy 复核架构与 `IMKTestRoot` 绑定；附件名带架构 |
| `packaging/macos/prepare-isolated-ci.py` | 目标根从「只允许 `/private/var/folders`」放宽为「接收设备系统临时目录内」：`/private/var/folders/**/T`、`/private/tmp`、`/tmp`、`/private/var/tmp`、`/var/tmp` 的直接子目录；仍要求 `lampyris-imk-<UUID>`、绝对规范化、无 `..`，拒绝真实数据目录 |
| `platforms/macos/tests/isolated-imk.py` | `build(root, arch)` 按架构切片构建；本机默认（`native`）行为不变；新增 `build_arches`/`macho_arches` |
| 测试 | `test-isolated-ci.py` 3 项、`test-isolated-imk.py` 6 项全绿；`make verify` 全绿 |
| 文档 | `ADR-216`、`packaging/macos/ISOLATED-CI.md` |

安全约束保持：**签名前**才把 `IMKTestRoot` 重绑到接收方目标根，此后不在 runner 上执行该包；
凭据仅 main、Actions 固定 commit、签名材料 always 清理。

## 2. 出包与核对（run `39269308347`，commit `c60bd88`，success）

- 私有根：`/private/var/folders/x7/hhbm75rn6vz_37yjj5rsq9yc0000gn/T/lampyris-imk-fd15c596-…`（0700 + 0600 `owner`）。
- 产物：`LampyrisIMKTest.zip`，SHA-256 `d14a395bdb25bdd763ecdc9a3865d1ae73c953cb386cb89a6b0daa6ebae39c8d`；
  包内 `TARGET-ROOT.txt`、`TARGET-ARCH.txt`（requested=built=x86_64）、`SOURCE-COMMIT.txt` = `c60bd88…`。
- 执行文件：`x86_64`，身份 `cn.jokerhub.inputmethod.LampyrisIMKTest.fd15c596-…`；
  `codesign --verify --strict` ✓、`stapler validate` ✓、`spctl` → **accepted / `source=Notarized Developer ID`（Team `2N62934Y28`）**；
  `IMKTestRoot` 与目标根一致（证据 `102-package-verify.txt`）。

## 3. 安装（未动生产包与用户数据）

- 解压后复制为私有根内 `LampyrisIMKTest.app` 与 `~/Library/Input Methods/LampyrisIMKTest-fd15c596-….app`，
  并做 `lsregister -f`；`source-state` 编译完成。
- 装前/装后：生产 `Lampyris.app` 执行 SHA `681fb1c8…`、宿主 91040 未停止、真实 `config.toml` `809e2cae…` 未变；
  本轮**没有**设置 `LAMPYRIS_SUPPORT_DIR`（隔离包自身把配置写明在私有根内）。
- 隔离包启动前置（`IMKTestRoot`、UUID、0700/0600 所有权、签名）由包自身与探针再次校验。

## 4. 阻塞：系统发现需要一次重新登录（BLOCKED，非 FAIL）

| 检查 | 结果 |
|---|---|
| TIS 枚举 | 2 个自有身份（父源 + `.default` 模式），`enableCapable=true`；`.default` 模式 `enabled=true`、`selectCapable=true`（证据 `02-state-after-install.json`） |
| 系统设置「＋」列表 | **看不到**「萤火虫隔离验收 fd15c596」（用户确认） |
| 菜单栏输入法菜单 | **看不到**（用户确认） |
| 尝试启用父源并选择独有模式 | **`TISSelectInputSource` 返回 `-50`**，父源 `enabled` 仍为 0（证据 `102-select-blocked.txt`） |
| 状态恢复 | `restore-original` 正常，当前源回到用户原源；真实数据未变（`05-state-after-restore.json`） |

与 ADR-130/131 在设备 B 的实测一致：**公证包本身通过校验，但新装第三方输入法的系统发现发生在登录时**；
不重新登录时源不可见、`TISSelectInputSource = -50`。本轮不绕过（不写 `com.apple.HIToolbox` 偏好、不伪造启用）。

## 5. 重新登录后的续做步骤（交接用）

1. 校验私有根仍存在且为 0700+`owner`；若登录后临时根被清掉，按 ADR-131 在**同一 UUID 路径**独占重建
   （不恢复测试配置内容），并重新编译 `source-state`。
2. 复核已装包：`codesign --verify --strict`、`stapler`、`IMKTestRoot`、UUID 与私有根一致。
3. 系统设置添加「萤火虫隔离验收 fd15c596」（或确认 TIS 两个自有身份已 enabled）。
4. 以当时实际原源刷新 `selection-state.json`，再跑
   `run-installed-textedit-probe.py` / `run-installed-safari-probe.py` / `run-installed-terminal-probe.py`
   的 normal/failure/INT/TERM；每批发键前 `guard-focus.sh`，中途失焦立即记 BLOCKED。
5. 收尾：`source-state restore-original` → `disable-owned` → 移除输入源与实体包 → 删除私有根 →
   回读生产包执行 SHA/宿主/真实数据摘要，写入本报告并把报告 101 对应项从 BLOCKED 改判。

## 证据

- `platforms/macos/build/acceptance-it14-a/`（本地，不入库）
- 入库小证据：`docs/reviews/102-evidence/`（包核对、TIS 状态、`-50` 阻塞、恢复后状态）
