# 181 隔离更新安装位置绑定（第二阶段，未签名、未安装）

## 本轮范围

承接 ADR-287 第一阶段（PR #145，main `37323e9`）的目标契约，本批只做**运行时的安装位置绑定与守卫**，不构建、不签名、不安装任何更新程序或输入法包。

| 部分 | 行为 |
|---|---|
| 生产更新程序 | `LampyrisTestOnly` 缺失时解析为 `~/Library/Input Methods` + `~/Library/Application Support/Lampyris/updates` + 生产身份，行为与之前一致 |
| 测试构建 | 仅在签名包同时带 `LampyrisTestOnly=true`、`LampyrisIsolatedIdentity`、`LampyrisIsolatedRoot` 时，才改用根内的 `Input Methods`/`updates` 与 `LampyrisIMKTest.<UUID>` 目标 |
| 绑定校验 | 包标识必须等于 `cn.jokerhub.Lampyris.WebsiteUpdateCheckTest.<UUID>`；UUID 与隔离身份、根目录名一致；根不是符号链接、属主为当前用户、权限不含 group/other 位、`owner` 标记 0600 且内容等于目录名；根必须位于设备私有 `T` 目录或 `LampyrisIMKDev` 开发根 |
| 失败处理 | 绑定不完整或校验失败时窗口显示“更新已停用”并禁用检查，**不回退生产目录** |
| 生产构建 | `build.py` 在写 Info.plist 前拒绝这三个隔离键，防止误把测试绑定打进发行更新程序 |

## 验证（全部离线，无网络请求）

- `make macos-updater-tests`：该包 38 项 + 核心 7 项 PASS，新增 5 项位置测试覆盖生产解析、临时根接受、开发根接受、缺失绑定/身份不符/生产身份/错误包名拒绝、符号链接/权限过宽/标记不符/根外目录/缺失标记拒绝。
- `make macos-updater-build`：PASS；实际产物的 Info.plist 只含 `cn.jokerhub.Lampyris.WebsiteUpdateCheck`，不含任何隔离键。
- 新增 `packaging/macos/tests/test-updater-isolation.py`：3 项结构回归（生产构建拒写隔离键、运行时要求 flag/身份/拥有根、窗口不近似回退生产）。
- 隔离根实验只在用户私有临时目录内创建 `lampyris-imk-<UUID>` 并删除；未触碰生产包、真实 `config.toml`、词库、输入源。

## 仍未关闭（BLOCKED）

1. **没有签名隔离更新程序**：需要新测试构建号、测试用更新公钥/私钥（私钥不进客户端）与 CI 签名/公证流程；本轮只改了源码。
2. **没有可安装的隔离载荷**：需要同源构建的 `LampyrisIMKTest.app`，且经 Developer ID + 公证，`validateCandidate` 才会放行；本机无法在无人工授权的情况下完成公证。
3. **没有受控 HTTPS 签名测试 feed**：需要先决定提供方（项目自有静态托管 / 临时 CI 端点 / 本机受控 TLS）及公开与授权边界；不得用环境变量或改 hosts/系统信任库绕过。
4. 因此更新 UI 的下载成功/失败/取消、安装成功、失败回滚、临时目录清理与宿主长期动态零外联**仍未原生验证**；`build20` 诊断附件不得用于安装。
5. 生产包、真实配置、词库、输入源本轮完全未动；本报告不作为任何发布或升级依据。
