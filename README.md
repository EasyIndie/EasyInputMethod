# 萤火虫输入法（EasyInputMethod）

<img src="assets/icons/yinghuo-official-icon.png" width="160" alt="萤火虫官方标识：飞行萤火虫">

> 一款**跨平台、开源可审计、默认离线、只做核心输入**的中文输入法。
>
> **状态：macOS 首版功能已实现，历史实机验收已记录；当前推进审计发现的可靠性修复与最终发布候选验收（见 [迭代计划](docs/迭代计划.md)）。** 日常隔离调试运行 `make macos-dev`；尚未达到正式发布验收。

## 这是什么

- **默认混合输入**：五笔优先，想不起码时自动用拼音兜底，不用切模式。
- **隐私优先**：输入引擎与输入法宿主零网络、零遥测、无广告、无账号；独立网站更新检查原型仅显式检查可联网，缺发布配置默认关闭，不随默认输入法包分发。
- **小而美**：只做输入本身，不做云同步/皮肤商店/AI 写作/内容分发。
- **跨平台**：macOS → Windows → Linux → Android/iOS，共享同一套 Rust 引擎。
- **开源可审计**：核心 `forbid(unsafe_code)`；码表可复现生成。
- **许可证**：GPL-3.0-or-later（防止被闭源包装成劣币）。

## 更新与可复验（v0.1.0 起）

- 入口：输入法菜单 → **检查更新…**（已装独立更新程序则打开其窗口，否则打开 Releases 页面；宿主本身不联网）。
- 更新程序：**DMG 与 ZIP 都自带，安装器/`install.sh` 会把它装到 `~/Applications/LampyrisUpdateCheck.app`**（ADR-295）；也可手动放 Release 里的 `LampyrisUpdateCheck-<version>.zip`，**不需要改名**。宿主与卸载器按 bundle id `cn.jokerhub.Lampyris.WebsiteUpdateCheck` 定位它（ADR-294）。它不随系统启动、不后台检查，只在点菜单时运行。
- 卸载：装完后不需要留着 DMG——更新窗口里有「卸载萤火虫…」（默认保留配置与词库；也可 `LampyrisUpdateCheck --uninstall [--purge-data]`，ADR-296）。
- 默认更新源：`https://github.com/EasyIndie/EasyInputMethod/releases/latest/download/appcast.xml`
  （设置 → 更新 → 更新来源 可改成自建 https 地址；留空即用官方源）。
- **更新包必须由项目 Ed25519 私钥签名**；公钥是公开值，随源码提交在
  [`packaging/macos/update-public-key.txt`](packaging/macos/update-public-key.txt)，
  同样写入签名包 `SUPublicEDKey`。改更新源**不需要**任何账号/凭据，但换的源必须发布**同一把私钥**签出的包，
  否则验签失败、不会安装。
- 公钥（Base64，32 字节）与指纹（SHA-256，原始字节）：

  ```
  IM+EfMnSZxxbrVFN8Wd8AD/RR4/FSUSzNzKostv40fw=
  0fdcb0db6178a54d5c966dee3ef9903f7f33fb0df865689b8b847c4667051c7d
  ```

> **更新私钥不可丢。** 私钥只保存在 GitHub Secret `LAMPYRIS_UPDATE_PRIVATE_KEY` 和离线备份中；
> Secret 只写不可读，不能当备份。丢失后无法再为已安装客户端签更新，只能让用户手动重装带新公钥的版本。
> 请务必在密码管理器与离线加密介质各保留一份 PEM，并定期核对上面的指纹。

- 独立复验（不依赖服务器信任）：

  ```sh
  # 仓库公钥 → Ed25519 SPKI DER → PEM
  { printf '\x30\x2a\x30\x05\x06\x03\x2b\x65\x70\x03\x21\x00'; \
    python3 -c 'import base64,sys;sys.stdout.buffer.write(base64.b64decode(open("packaging/macos/update-public-key.txt").read()))'; } > pub.der
  openssl pkey -pubin -inform DER -in pub.der -out pub.pem

  # 从 Release 下载 appcast.xml，取出 sparkle:edSignature 解码为 sig.bin 后：
  openssl pkeyutl -verify -rawin -pubin -inkey pub.pem \
    -in Lampyris-0.1.0-universal.zip -sigfile sig.bin
  ```

- 签名 tag 校验**待启用**：提交 `packaging/git-allowed-signers`（允许的 SSH/GPG 签名者）后，Release 工作流会强制 `git tag -v`；详见 [更新发布流程](docs/更新发布流程.md)。
- 多项目密钥统一保管见 [密钥与凭据管理](docs/密钥与凭据管理.md)；大陆网络可配置区域镜像自动回退，见 [更新源与镜像](docs/更新源与镜像.md)。

## 名字

**萤火虫** —— 小、自带微光（不依赖云端）、安静不打扰。

英文/包名 **`Lampyris`**（读 /læmˈpɪərɪs/，希腊语“发光的虫”，萤科一属；寓意“自带微光”）。不使用 `Firefly`（与 Adobe Firefly 等冲突）。bundle 标识 `cn.jokerhub.inputmethod.Lampyris`，见 ADR-056。

## 下载与发布

发布渠道为 **GitHub Release（产物）+ GitHub Pages（下载指引）**（ADR-065）：

- 下载最新版：<https://github.com/EasyIndie/EasyInputMethod/releases/latest> —— 同一 Release 含二进制包与**对应源码包**（GPL-3.0 §6(d)）。
- 项目主页（GitHub Pages）：由 `site/` 部署，见仓库 Settings → Pages。

> 仓库**已公开**（GPL-3.0-or-later）；发布由 tag `v*` 触发（**不自动发布**），首版 `v0.1.0` 待打 tag。

## 目录

```
AGENTS.md          # ★ AI 代理入口（所有工具的统一规则）
HANDOFF.md         # ★ 会话交接（当前状态，每次会话更新）
CONTRIBUTING.md    # 贡献规范（DCO / Conventional Commits）
ROADMAP.md         # 任务清单（带复选框）
Makefile           # make verify 等规范命令
.agents/skills/    # Agent Skills（可复用操作流程）
docs/              # 设计与决策文档
crates/            # Rust 工作区（P1-M0 创建）
platforms/ data/ tools/ packaging/ scripts/
```

## 文档

请从 **[docs/技术方案.md](docs/技术方案.md)** 开始；索引见 [docs/README.md](docs/README.md)。

| 文档 | 内容 |
|---|---|
| [技术方案.md](docs/技术方案.md) | 权威总方案 |
| [配置架构.md](docs/配置架构.md) | 配置子系统（真值唯一 / 实时生效） |
| [开发工作流.md](docs/开发工作流.md) | 迭代与 CI 分层（单人 / 团队） |
| [数据来源与许可.md](docs/数据来源与许可.md) | 数据合规 |
| [隐私与安全.md](docs/隐私与安全.md) | 安全工程 |
| [决策记录.md](docs/决策记录.md) | ADR |
| [参考与致谢.md](docs/参考与致谢.md) | 借鉴来源 |

## AI 辅助开发

本仓库为长期与 AI 代理共同迭代而组织，支持 **pi / Codex / Claude Code**：

- **[AGENTS.md](AGENTS.md)** —— 唯一入口与规则来源（pi 与 Codex 直接读取）。
- **[HANDOFF.md](HANDOFF.md)** —— **跨会话/跨工具交接**：当前状态、下一步、阻塞（每次会话结束更新）。
- **[CLAUDE.md](CLAUDE.md)** —— 指向 AGENTS.md 的兼容指针（Claude Code）。
- **[ROADMAP.md](ROADMAP.md)** —— AI 从这里取任务（一次一个）。
- **`.agents/skills/`** —— 可复用操作流程：`update-handoff`、`add-config-option`、`add-data-source`、`add-engine`、`verify-privacy`（`.claude/skills` 为指向它的软链，供 Claude Code 读取）。
- **[CONTRIBUTING.md](CONTRIBUTING.md)** —— 提交规范与铁律。
- `make verify` —— 提交前的统一验证（格式 / lint / 测试 / 许可 / 隐私断言）。

## 路线图（摘要）

| 阶段 | 目标 |
|---|---|
| **P1** | macOS 上"默认可混输"的完整五笔输入法 |
| P2 | 拼音体验打磨 + 自研引擎 |
| P3 | Windows（Rust TSF） |
| P4 | Linux（Fcitx5） |
| P5 | Android / iOS |
| P6 | 本地语音（可选，纯本地） |

## 许可

GPL-3.0-or-later，见 [LICENSE](./LICENSE)。
项目名称与 Logo 保留权利；fork 版本请改名。

## 项目图标

[图标资产目录](assets/icons/README.md)保留 V1–V5；当前首选 **V4 单线标志**，以简洁线条表达项目定位。
