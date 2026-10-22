# 140 App Store 沙盒原型（ADR-260）

## 交付

- `platforms/macos/Lampyris-sandbox.entitlements`：仅 `app-sandbox` + `mach-register` 临时例外
  （`cn.jokerhub.inputmethod.Lampyris_Connection`），**不申请**网络、UserDefaults 或任意文件访问。
- `platforms/macos/build.sh --sandbox`：常规构建后再产出一份 `build/LampyrisSandbox.app`（ad-hoc、不安装、不分发）。
- `platforms/macos/tests/sandbox-config-probe.swift` + `packaging/macos/tests/test-sandbox-config.py`：
  离线回归两条
  1. 沙盒进程内按同一路径规则（Application Support + Lampyris）走 `ime_config_init/set/get`，配置只落在
     `~/Library/Containers/cn.jokerhub.inputmethod.Lampyris.sandboxprobe/Data/...`，真实 `~/Library/Application Support/Lampyris` 不被写入；
  2. `Info.plist` 的 `InputMethodConnectionName` 必须等于 `CFBundleIdentifier + "_Connection"`、输入模式清单存在，
     entitlements 含 app-sandbox、mach-register 名称与 bundle id 一致、且不含网络权限；`build.sh` 保留 `--sandbox` 入口。

## 实测（本机 macOS 27 / arm64）

| 项 | 结果 |
|---|---|
| 沙盒包构建 | `build/LampyrisSandbox.app`，ad-hoc，entitlements 与上述一致 |
| 启动 | PID 49552 正常运行，`libsystem_secinit` 记录 AppSandbox 初始化，无 deny 日志 |
| 容器 | `~/Library/Containers/cn.jokerhub.inputmethod.Lampyris/` 自动创建 |
| 配置根 | 容器内 `Data/Library/Application Support/Lampyris`；真实 Application Support 目录 mtime 未变 |
| 配置读写（探针） | `ime_config_init` 返回 0，`candidate.count = 7` 写入并读回，文件位于容器内 |
| 离线回归 | 2 项 XCTest 风格断言全 PASS，并入 `macos-offline-tests` 自动发现 |

## Go / No-go

**条件性 go**：沙盒不会破坏「配置唯一」「零网络」「学习数据本地」三条核心承诺，连接名与输入模式声明也可机器校验。
但以下阻塞项**必须在真实商店构建上验证**，当前不算可行：

1. Apple Distribution 签名与描述文件、MAS 上传/审核（本机只有 Developer ID，未做）；
2. MAS 安装位置与 IMK 注册路径（`/Applications` vs `~/Library/Input Methods`）以及首次启用/切源体验；
3. 商店版去掉自更新后的升级路径与用户提示（只能等 App Store 更新）；
4. 审核对「输入法」类别的额外要求、隐私标签与 GPL 许可证在商店渠道的呈现方式。

## 边界

- 未安装沙盒包、未注册输入源、未改动已装的 build6 与生产数据；原型进程已精确停止，容器保留供复核。
- 无 tag / 无 Release；网站渠道仍是唯一候选路径。
