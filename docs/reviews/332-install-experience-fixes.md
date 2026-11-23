# 332 — 第三方机器的首次真实安装：四处问题与修复（ADR-390，2026-11-23）

> 触发：1.4.0 发布后，在一台**不属于开发机的 MacBook Air、普通（非管理员）帐户**上，按产品页下载 → 打开 DMG →
> 双击「安装萤火虫」走第一次真实安装。此前 1.0–1.4 的所有安装验收都在有 Xcode / Command Line Tools 的
> `air`（joker）与 `pro`（bot）上做，**没有走过「干净工具链 + 普通帐户」这条路径**。
> 结论：四处问题全部可复现、已定位并修好；干净机器复验要等下一个候选包（`docs/待办与积压.md` P0-6）。

## 1. 现场（用户提供）

| # | 现象 | 截图/文案 |
|---|---|---|
| 1 | 点「安装」后立即失败 | `安装失败 / 安装更新程序失败：候选校验失败：/usr/bin/xcrun 校验失败` |
| 2 | `LampyrisUpdateCheck.app` 双击打不开；`Lampyris.app` 也一样 | Finder 无任何反应，无对话框 |
| 3 | 「安装萤火虫」窗口顶部内容看不全 | 头像与「萤火虫」标题被标题栏压住一半 |
| 4 | 四个 app 图标一样、外面多一圈白 | DMG 里安装器/卸载器/输入法/更新程序四张图标无法区分 |

## 2. 定位

| # | 根因 | 证据 |
|---|---|---|
| 1 | 安装期公证校验调用 `/usr/bin/xcrun stapler validate`。`xcrun` 只在装了 Command Line Tools 的机器上可用，普通帐户的干净 Mac 上**必定**失败；验签链最后一步把正常包判成「候选不合格」 | 发布 DMG 上 `codesign --verify`/`-dv`/`spctl` 全 PASS，说明包没问题，只有 `xcrun` 这一步会挂；`install.sh` 同一句 |
| 2 | 更新程序只认 `--ui`：`arguments` 为空时打印「网站更新检查默认关闭…」后**直接返回退出**；Finder 双击不带参数。输入法本体是 `LSBackgroundOnly` + `LSUIElement`，双击本来就没有窗口 | `WebsiteUpdateCheck.swift` 的 `arguments == ["--ui"]`；`Info.plist` 两个背景键 |
| 3 | 安装器手写 `stack.frame = (0, 0, 520, 326)`，但内容视图只有 286pt；多出的 40pt 从 y=0 往上长，被裁掉的正好是最上面的头像与标题 | 复现构建：窗口 520×314（修复前 520×286、header 不可见） |
| 4 | 安装器/卸载器/更新程序都拷同一份 `yinghuo-official-app.icns`，该 ICNS 又由带白边圆角的 `yinghuo-official-macos.png` 生成；macOS 26 把旧式图标放进白色托板 | 发布 DMG 里四张图标逐字节相同；ICNS 内部 1024 图四周确有白色画布 |

## 3. 修复

| # | 改动 | 文件 |
|---|---|---|
| 1 | 公证票据就是 bundle 里的 `Contents/CodeResources`（`stapler` 装订物）：安装期只检查它在且非空，「Apple 是否认可」交给 `spctl --assess --type execute`（离线只认票据）。**不放宽**身份/Developer ID/hardened runtime/票据/Gatekeeper 任一项，只换工具 | `InstallCore/…/DefaultInstallEnvironment.swift`、`platforms/macos/install.sh`（输入法与更新程序两处） |
| 2 | 无参数启动 = 进窗口，与 `--ui` 同一入口；进窗口不联网，仍只有用户按「检查更新」才发请求；`--check`/`--verify-payload`/`--drill-run` 不变 | `Updater/Sources/WebsiteUpdateCheck/WebsiteUpdateCheck.swift` |
| 3 | 内容视图改约束布局（宽度固定 520），窗口高度取 `fittingSize` 与 286pt 的较大值，文案变化后重算并保持左上角不动 | `Installer/Sources/LampyrisInstaller/main.swift` |
| 4 | ICNS 母版换成 full-bleed 的 `yinghuo-official-icon.png`；安装器/卸载器/更新程序各生成一张「萤火虫 + 角色角标」（`arrow.down` / `trash` / `arrow.triangle.2.circlepath`） | `tools/build-macos-icons.sh`（新）、`tools/render-role-icon.swift`（新）、三个 `build.py`、`assets/icons/README.md`、`platforms/macos/README.md` |

## 4. 本机验证（有 Xcode，只验布局/图标/契约）

| 项 | 结果 |
|---|---|
| 安装器窗口（准备安装态） | 520×314，头像、标题、「版本」、「准备安装」、两个按钮、页脚全部可见 |
| 安装器窗口（无法安装态，长文案换行） | 同样 520×314，两行说明完整显示，顶部不再被裁 |
| DMG 预览（`make-dmg.sh` + 本地未签名二进制） | 四个图标：安装器↓ / 卸载器🗑 / 输入法（纯萤火虫）/ 更新程序↻，**无白色托板** |
| 自动化 | `make verify` PASS（1,197 产物、0 网络符号）；`test-install.py` 16 例、`test-dmg-updater.py` 19 例、`test-install-core.py`、docs 卫生/同步 全 PASS |

新增/改写的契约测试：

- `test-install.py::test_verification_never_needs_the_xcode_toolchain`：`install.sh` 不得出现 `xcrun stapler`，
  缺 `Contents/CodeResources` 必须拒绝安装且不落盘；夹具补齐票据文件。
- `test-dmg-updater.py`：核心里是 `Contents/CodeResources` + `spctl` 且无 `/usr/bin/xcrun`；
  更新程序无参数时与 `--ui` 同一入口。

## 5. 真机复验（P0-6，已完成）

1.4.1 / build 49（tag `v1.4.1` → `8d0416a`，DMG `ad95d108…`）发布后，用户在这台 MacBook Air（**普通帐户、无 Xcode/CLT**）
走产品页真实下载链路复验，四项全 **PASS**：安装完成且不再报 xcrun、更新程序双击出窗口、安装器窗口顶部完整、四个图标可区分无白边。
记录见 `docs/releases/1.4.1.md` §4。证据边界：只做人工功能确认，未在该机采集执行 SHA。

## 6. 仍未决策

- 是否把 `Lampyris.app`（背景程序，双击无窗口）从 DMG 顶层挪进安装器 bundle：交互/打包结构变更，另行评估。
