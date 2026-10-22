# 139 已验签的原地升级与回滚（ADR-259）

## 交付

`packaging/macos/upgrade.py` 把生产输入法的原地升级固定成一条可审计顺序：

1. **验签**：调用已签名的 `LampyrisUpdateCheck --verify-payload <zip> <签名>`（ADR-256 的 Ed25519 校验）；
   失败时**不解包、不创建支持目录、更不碰安装目录**。
2. **解包**：`ditto -x -k` 到 0700 私有暂存目录，要求顶层有 `Lampyris.app`。
3. **候选校验**：`CFBundleIdentifier == cn.jokerhub.inputmethod.Lampyris`、可执行文件存在且可执行、
   `codesign --verify --strict --deep`、Developer ID + hardened runtime、`stapler validate`、`spctl` accepted。
4. **停精确宿主**：`lsof -t <已安装可执行文件>` 取持有者，逐个校验 `ps -o comm=` 与可执行路径完全一致后 SIGTERM，
   5s 内未退出即失败（不替换）。
5. **备份 + 原子替换**：旧包改名为备份目录中的 `Lampyris.app`（同一卷 rename），候选再 rename 到目标位置。
6. **落地后复验**：对目标路径重跑同一候选校验；失败则把新包移到 `rejected.app` 并恢复旧包。
7. **receipt**：成功写 0600 JSON（负载 SHA-256、签名、前后执行 SHA、备份路径），放在
   `~/Library/Application Support/Lampyris/updates/receipts/`。

默认 dry-run；真正写入必须 `--apply` 且必须提供已签名的验签器，避免误以为「默认就会升级」。

## 离线回归（8 项，全 PASS）

`packaging/macos/tests/test-upgrade.py`（注入 hooks，使用临时目录与 `ditto` 夹具，不触碰真实输入法）：

1. 全新安装放置 bundle 并写私有 receipt（0600，payload SHA 正确）；
2. 升级保留旧包为备份、且停宿主发生在替换之前；
3. 落地后复验失败 → 恢复旧包；
4. 验签失败 → 旧包不动、不创建支持目录、不停宿主；
5. 停宿主失败 → 旧包不动；
6. dry-run → 不停宿主、不替换；
7. 目标是符号链接 → 拒绝；
8. 负载里没有 `Lampyris.app` → 拒绝且不停宿主。

已并入 `make macos-offline-tests` 自动发现（42 个离线文件）。

## 仍未完成

- **没有真实下载**：不请求 feed、不建 URLSession 下载器；当前入口要求本地已下载的负载 + 签名。
- **没有真实 feed/公钥**：真实升级演练需要在签名包上配置正式公钥，并确认真实 ZIP 的签名由离线私钥签发。
- **没有自动切源/重启**：升级后输入源由系统沿用；首次启用体验与宿主自动重启仍需实机演练（含失败恢复）。
- **系统域**（`/Library/Input Methods`）与 App Store 渠道不使用本脚本（ADR-257）。

## 边界

- 未在真实安装目录执行 `--apply`，未改动已装 build6、生产数据与输入源。
- 无 tag / Release；不创建后台任务、不写第二份配置。
