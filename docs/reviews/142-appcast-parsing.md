# 142 appcast 解析与版本选择（ADR-262）

## 交付

- `packaging/macos/feed.py`：与 Swift 更新程序同一套 appcast 规则的纯函数实现（`parse_appcast` / `newest_release`），
  以及 `Build` 点分版本比较（≤8 段、忽略尾部 0、≤128 字节）。
- `packaging/macos/upgrade.py`：新增 `--feed-file` / `--feed-url` / `--current-build`：
  - 未发现更高 build → 输出 `{"result":"up-to-date","current":"6"}` 并以 0 退出，不下载；
  - 发现更新 → 用 feed 的 `url` 下载、用 `sparkle:edSignature` 验签，再走 ADR-259 的替换/回滚；
  - `--allow-file-url` 仍仅限离线测试。
- `packaging/macos/tests/test-feed.py`（11 项）与 `test-upgrade.py` 新增 1 项 CLI 回归。

## 规则（与 Swift 一致）

| 项 | 规则 |
|---|---|
| 协议 | 下载地址仅 https，禁止 user/password/fragment；file:// 需显式测试开关 |
| 大小 | feed ≤ 1MiB；enclosure `length` 必须为正整数 |
| XML | 拒绝 `<!DOCTYPE` / `<!ENTITY`，深度 ≤16，根元素 `rss`，恰好一个 `channel` |
| 条目 | item ≤1000；每 item 恰好一个 enclosure；必须含 `sparkle:version`/`url`/`sparkle:edSignature` |
| 签名 | Base64、恰好 64 字节（长度检查≠验签，真正校验在下载后） |
| 选择 | build > current 的最高项；点分比较、忽略尾部 0 |

## 离线回归

- `test-feed.py`：最高版本选择、无更新、版本归一化与非法格式、DTD/ENTITY、超大 feed、非 https/带凭据/带 fragment、
  缺字段/坏 Base64/零长度、enclosure 数量、根/多 channel、>1000 项、嵌套过深 —— **11/11 PASS**。
- `test-upgrade.py`：新增「本地 feed 已是最新 → 退出 0 且不下载」——**16/16 PASS**（含下载器与替换/回滚）。

## 仍未完成

- 真实 feed/公钥与 HTTPS 演练；版本/架构/渠道筛选（当前只比 build）；增量包；灰度与回滚策略。
- feed 元数据仍不可信：安全边界依旧是下载后的 Ed25519 验签与候选校验。

## 边界

- 未联网、未改动已装 build6、未触碰生产数据；无 tag / Release。
