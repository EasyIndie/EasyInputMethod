# 182 隔离更新 drill：测试 feed 定案与隔离更新程序构建入口

## 决策与来源

- 用户选择 ADR-288 方案 a：drill 使用项目自有 Pages 子路径。
- 实测 `https://input.jokerhub.cn/`：HTTP/2 200，证书 `CN=input.jokerhub.cn`（Let's Encrypt，2026-10-23 至 2027-01-21），未知路径正确 404；`https://easyindie.github.io/EasyInputMethod/` 会 301 到 `http://input.jokerhub.cn/`，属降级跳转，**不得**作为 feed。
- 因此 drill feed 固定 `https://input.jokerhub.cn/drill/appcast.xml`，载荷同目录。

## 本轮实现

- `platforms/macos/Updater/build.py` 新增显式隔离构建参数：`--isolated-root`、`--isolated-identity`、`--test-build`、`--output`。三项必须同时给出，否则直接失败。
  - 身份必须是 `cn.jokerhub.inputmethod.LampyrisIMKTest.<规范小写UUID>`，目录名必须是 `lampyris-imk-<UUID>` 且 UUID 与身份一致；
  - 根必须在设备私有 `T` 目录（`/var/folders/…/T` 或 `/private/var/folders/…/T`）或 `LampyrisIMKDev` 开发根内，非符号链接、属主为当前用户、权限不宽于 0700、`owner` 标记 0600 且内容为目录名；
  - 测试构建号必须是高于当前生产构建的正整数；
  - 产出包标识 `cn.jokerhub.Lampyris.WebsiteUpdateCheckTest.<UUID>`、显示名「萤火虫 更新（测试）」，并写入 `LampyrisTestOnly`/`LampyrisIsolatedRoot`/`LampyrisIsolatedIdentity`。
- 生产构建路径不变：三个隔离键只在 `isolated` 分支出现，且非隔离构建仍强制拒绝它们。

## 本地验证（无签名、无安装、无网络）

| 项 | 结果 |
|---|---|
| 隔离构建 | `build.py --isolated-root … --isolated-identity … --test-build 901 --feed-url https://input.jokerhub.cn/drill/appcast.xml` 成功；Info.plist 读回包标识 `…WebsiteUpdateCheckTest.ac71cd44-…`、build 901、`LampyrisTestOnly=True`、根与身份与实参一致 |
| 生产重建 | 包标识仍为 `cn.jokerhub.Lampyris.WebsiteUpdateCheck`、build 20、无任何隔离键 |
| 运行行为 | 隔离二进制无参数运行只打印「默认关闭…不会联网」并退出 0；`--verify-payload` 传非法签名退出 1 且提示不安装 |
| 结构回归 | `packaging/macos/tests/test-updater-isolation.py` 4 项 PASS（新增三项参数/构建号/根守卫断言） |

私有根只在系统临时目录创建（`lampyris-imk-<UUID>`，0700 + 0600 owner），未触碰生产包、真实 `config.toml`、词库与输入源；未读取生产更新私钥。

## 仍未完成

1. main-only drill 工作流：临时 Ed25519 密钥、隔离载荷签名+公证、appcast 生成与 artifact 上传。
2. Pages 合并发布任务与 `site/` 不受影响的验证，以及 drill 后的下线流程。
3. 本机原生执行：检查 → 下载（经 `input.jokerhub.cn`）→ 验签 → 取消/失败/成功/回滚，并回读生产包/配置/词库/输入源未变。
4. 该 drill 只覆盖独立更新程序路径；宿主 IMK 行为、长期动态零外联与最终 RC 矩阵仍另计。
