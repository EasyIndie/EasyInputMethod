# 145 更新来源可配置（ADR-264）

## 交付

1. **配置项** `update.feed_url`（`ime-config` Schema，新类型 `Url`）：
   - 只接受空值或 `https://` 地址；拒绝凭据（`@`）、fragment（`#`）、空白与空主机；
   - 默认空 = 官方 GitHub 发布源；设置界面自动多出「更新」分区（Schema 驱动，无手写界面）。
2. **默认 GitHub 源**：`https://github.com/EasyIndie/EasyInputMethod/releases/latest/download/appcast.xml`
   （写入 `Updater/build.py` 的 `SUFeedURL`；用户配置非空时覆盖）。
3. **信任锚固定**：`SUPublicEDKey` 只来自签名包，用户配置不能替换；feed 只决定"去哪拿元数据/负载"。
4. **更新程序读配置**：`WebsiteUpdateCheck` 链接 `ime-config` 静态库，读取 `update.feed_url`；
   优先级：用户配置 → `SUFeedURL`。仍是独立程序、默认关闭、不随宿主分发、宿主零网络。
5. **GitHub 重定向策略**：允许 `github.com` / `objects.githubusercontent.com` /
   `release-assets.githubusercontent.com` / `raw.githubusercontent.com`（必须 https）；
   其余跨主机重定向一律拒绝（Swift `RedirectGuard` 与 Python 下载器/feed 同步）。
6. **发布文档**：`docs/更新发布流程.md` 给出密钥生成、签名、appcast 生成、Actions 发版与轮换步骤。

## 验证

| 范围 | 结果 |
|---|---|
| `ime-config` | 17 项单测全过；新增 `update.feed_url` 接受空值/https、拒绝 http/凭据/fragment/非法；Schema 计数 19→20 |
| 设置界面 | `settings-presentation` 通过：5 分区、20 行，「更新」分区显示 `update.feed_url`，亮暗/最小窗离屏渲染正常 |
| 更新程序 | `swift test`（strict concurrency）全过；新增 `FeedSourceTests`：配置优先、非法回落、经 ime-config 读写 |
| 升级脚本 | 18 项离线回归全过；新增「允许 GitHub 资产主机重定向」「拒绝未允许主机」 |
| 构建 | `make macos-updater-build` 通过（先建 Rust 静态库，再链接 ime-config） |

## 边界与未完成

- **没有真实密钥、没有真实 GitHub feed、没有 HTTPS 演练**；`LAMPYRIS_UPDATE_PUBLIC_KEY/PRIVATE_KEY` 尚未配置。
- 未做镜像自动回退、渠道/架构筛选、灰度、下载确认/进度 UI。
- 用户改源不会降低验签要求；但改到恶意源时仍可能被引导下载任意包——只是安装前必然验签失败。
- 未改动已装 build6、生产数据与输入源；无 tag / Release。
