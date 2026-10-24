# 183 隔离更新 drill：真实 HTTPS 下载、验签、取消、篡改拒绝与原地升级

## 环境事实（先记录，避免误读）

- 当前会话是 SSH `Background` 会话：`launchctl managername = Background`、`SSH_CONNECTION` 存在。从中启动的 GUI 程序没有窗口服务器连接（`lsappinfo` 显示 `!cgsConnection`），AX 窗口枚举恒为 0，`screencapture` 报 “could not create image from display”。**本报告不含任何 UI 点击证据**。
- 本机系统代理为 `127.0.0.1:1082`（Shadowrocket），DNS 用 fake-IP。用户把 `input.jokerhub.cn` 规则改为走代理后，`URLSession` 取 feed 恢复正常（此前为 `NSURLErrorDomain -1005`）。
- 所有操作只写入私有根 `/private/var/folders/z0/…/T/lampyris-imk-ac71cd44-…/`，未安装到生产目录、未注册输入源、未改生产配置/词库。

## 被测对象（run `40139366666`，main `60d0713`）

| 对象 | 值 |
|---|---|
| feed | `https://input.jokerhub.cn/drill/appcast.xml`（200） |
| 载荷 ZIP | `LampyrisIMKTest-905-arm64.zip`，长度 `3901308`，SHA 校验通过（同目录 `.sha256`） |
| 载荷宿主 | `LampyrisIMKTest.app`，标识 `cn.jokerhub.inputmethod.LampyrisIMKTest.ac71cd44-…`，公证 + `stapler validate` 通过 |
| 更新程序 | `LampyrisUpdateCheckTest-905.zip` → `LampyrisUpdateCheck.app`，build **904**（低于载荷 905，故能发现更新） |
| 执行结果 | `installed_exec=74c786b9b19f39ef4a3d84bcca92fd84895b87e05105faaef066cd7a1207ea82` |

## 实测结果（`--drill-run`，无 UI，真实网络）

| 场景 | 输出 | 判定 |
|---|---|---|
| `cancel`（下载→验签后释放，等价确认框取消） | `signature=valid`、`temp_after_release=false`、`result=cancelled` | PASS：私有临时目录已清理 |
| `tamper`（下载后追加 1 字节再验签） | `signature=invalid`、`temp_after_release=false`、`result=rejected` | PASS：篡改被拒且清理 |
| `install`（先放置上一版 904 作为既有安装） | `previous=…/upgrades/upgrade-2026-10-24T22-41-29Z-BB051A20/backup/LampyrisIMKTest.app`、`temp_after_install=false`、`result=installed` | PASS：备份 + 替换 + 清理 |
| `install`（再次覆盖 905） | `previous=…/upgrade-…-C072E43A/backup/…`、`result=installed` | PASS：重复覆盖保留备份 |
| 落地复验 | 已装标识一致、`codesign --verify --strict --deep` 通过、`stapler validate` 通过、执行 SHA 与 receipt 一致 | PASS |
| receipt | 两份 `0600` JSON，位于 `<root>/updates/receipts/` | PASS |
| 生产侧 | 执行 SHA `c09c2d11…`、`config.toml` `3bc1117c…` 前后一致 | PASS（词库因用户持续输入变化，不归因本次） |

旁证：系统临时目录里唯一残留的 `lampyris-download-73D68563-…` 创建于 **2026-10-23 20:01**，早于本轮 drill 与 #142 修复，属旧版本遗留；本轮各次下载均未留下目录。

## 本轮发现

1. **fresh install 到没有 `Input Methods` 子目录的私有根会失败**（“couldn't be moved to Input Methods … folder doesn't exist”）。生产路径 `~/Library/Input Methods` 始终存在，因此不构成发布阻断；drill 改为先放置上一版 bundle（更贴近真实升级场景）后通过。是否让安装器自行创建目标目录，留作后续评估（需 ADR，因为改变“目录缺失”时的行为）。
2. `--drill-run` 首次实现持有 `payload` 的额外强引用，导致清理断言失真；已在 #152 修正为先释放再断言。

## 仍未关闭

- **UI 流程**：窗口内「检查更新 → 下载并安装 → 确认框取消/安装」的真实点击，必须在图形会话执行；本会话不可见、不可点。
- 原生回滚（落地后校验失败）只由 XCTest 覆盖，未在 drill 中注入。
- `/drill/` 仍在线（测试构建 905 + 更新程序 904），验收完成后需用普通 `Pages` 工作流重新部署下线，并删除私有根与测试更新程序。
- 上述结果只覆盖独立更新程序路径；输入宿主 IMK 行为、长期动态零外联与最终 RC 矩阵另计。
