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

## 追加：drill 工作流与本地签名链演练（同日）

- 新增 `.github/workflows/isolated-update-drill.yml`：main-only 手动触发，输入接收设备私有根、架构、测试构建号与 Pages 子路径。
  - build 作业：`make verify` + 隔离 IMK 回归 → 生成并**签名/公证/装订**隔离宿主 → 用临时 Ed25519 公钥构建隔离更新程序 → 载荷 ZIP 与 `appcast.xml`（`release-appcast.py`）→ artifact 保留 7 天 → 删除临时私钥、清理签名材料。
  - publish 作业：校验子路径只能是 `drill`/`drill-*`，把 artifact 合并到 `site/<drill>/` 后经 Pages 部署（与 `pages.yml` 共用 `pages` 并发组），测试二进制不进入 git 历史。
- 新增 `packaging/macos/tests/test-isolated-drill.py` 4 项结构回归（main-only、无生产密钥、临时密钥生成与删除、公证/子路径/无 tag-Release）。
- 本地演练（未联网、未签名、未安装）：用临时 Ed25519 密钥构建隔离更新程序并生成 appcast，再以 `--verify-payload` 用该 ZIP 与 appcast 内签名验证，输出「负载签名验证通过；尚未安装。」退出 0；私钥演练后即删。

仍未执行：真实 CI run、Pages 发布与下线、本机原生下载/取消/失败/成功/回滚。生产包、配置、词库、输入源未动。

## 追加：首次 drill run 结果与本机执行限制

- run `40109683347`（main `97e5927`）build 失败于 `prepare-isolated-ci.py`：设备 `TMPDIR` 是 `/var/folders/…/T` 写法，脚本只认 `/private/var/…`。修复合入 #149（main `ce1c5a1`）：临时根正则与运行时允许父目录同时接受两种写法，新增 Python/Swift 回归。
- run `40110592061`（main `ce1c5a1`）build + publish 均 success：
  - feed `https://input.jokerhub.cn/drill/appcast.xml` 返回 200，载荷 `https://input.jokerhub.cn/drill/LampyrisIMKTest-901-arm64.zip`（长度 3900964 与 appcast 一致，本地 SHA 校验通过）；
  - 载荷宿主 `cn.jokerhub.inputmethod.LampyrisIMKTest.ac71cd44-…`、可执行 `LampyrisIMKTest`、绑定根等于声明的私有根、`codesign --strict --deep` 通过、`stapler validate` 通过、`spctl` = Notarized Developer ID；
  - 更新程序 `cn.jokerhub.Lampyris.WebsiteUpdateCheckTest.ac71cd44-…`、build 901、Developer ID 签名（runtime）、ZIP SHA 校验通过。
- **本机执行限制（如实记录）**：当前会话是 SSH `Background` 会话（`launchctl managername = Background`、`SSH_CONNECTION` 存在）。从中启动的任何 GUI 程序都没有窗口服务器连接（`lsappinfo` 显示 `!cgsConnection`），AX 枚举所有应用窗口均为 0，`screencapture` 报 “could not create image from display”。因此**无法**在该会话里点击更新窗口，也不能用截图/AX 伪造 UI 证据。
- 补充实现（同批）：隔离构建新增 `--drill-run install|cancel|tamper` 无 UI 驱动，走同一套真实 feed → 下载 → 验签 → `DefaultInstallEnvironment` 公证校验 → 安装/回执/临时目录清理路径；非隔离构建一律拒绝（`location.isolated` 守卫）。UI 按钮点击与取消确认仍须在图形会话中由人工执行。
