# 147 更新公钥入库（ADR-266）

## 变化

- 新增并提交 `packaging/macos/update-public-key.txt`（Ed25519 32 字节 Base64 公钥）。
- `platforms/macos/Updater/build.py` 默认读取该文件写入 `SUPublicEDKey`；`--public-key` 仅作轮换/测试覆盖；
  构建时校验必须解码为 32 字节，否则报错。
- `release.yml` 与 `update-signing-check.yml` 不再从仓库 Variable/Secret 读取公钥；私钥仍只来自 Secret。
- `docs/更新发布流程.md` 增补「第三方独立复验」命令（仓库公钥 → SPKI DER → `openssl pkeyutl -verify`）。

## 验证

| 项 | 结果 |
|---|---|
| 公钥格式 | 解码 32 字节 |
| 本地构建 | `python3 platforms/macos/Updater/build.py` → Info.plist `SUPublicEDKey` 等于入库值、`SUFeedURL` 为 GitHub 默认 |
| 真实 Release 复验 | 用该构建的更新程序验证 `v0.1.0` 的 ZIP 与 appcast 签名：**通过**；篡改副本：**拒绝** |
| 新增回归 | `test-update-public-key.py` 4 项：公钥格式、build.py 默认入库、工作流不隐藏公钥、私钥未入库（扫描 Git 跟踪文件） |

## 说明

- 公钥按定义公开；放进 Secret 会让第三方无法复验、也让审计看不到信任锚。入库后 Release 的 appcast 可被任何人独立验证。
- 私钥仍只在 Secret（建议同时离线保存）；轮换需「旧钥签一个过渡版本 + 新钥入库并发布」，见发布文档。
- 未改动已装 build6/生产数据；无新 tag/Release。

## 下一步

真实安装演练仍待确认：`upgrade.py --apply` 会把生产包从旧 `17053e1` 升级到 `v0.1.0`（有备份与回滚），需要用户明确同意。
