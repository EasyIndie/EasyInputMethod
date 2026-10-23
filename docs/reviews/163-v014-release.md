# 163 v0.1.4：Shift 切换 HUD + 更新进度条修复上线

## 发布

| 资产 | 说明 |
|---|---|
| `Lampyris-0.1.4-universal.zip` | build 12；已签名/公证 |
| `LampyrisUpdateCheck-0.1.4.zip` | 更新程序 build 12（静态链接） |
| `appcast.xml` | `sparkle:version=12` |

## 修复内容（ADR-277）

- 单独 Shift 切换中英：键盘 `flagsChanged` 路径现在与菜单路径一样调用 `showStateFeedback`，弹出「中文/英文」HUD。
- 更新窗口进度条：仅在下载阶段显示；检查/空闲/完成/失败时隐藏，安装阶段不再残留空进度条。

## 本机安装

- 生产包升级到 **0.1.4 / build12**（执行 `17d2a3dc…`），旧 build11（`d489dd79…`）备份在 `updates/build12-backup/`；
- 更新程序 0.1.4 已装到 `~/Applications/Lampyris Update.app`；
- 配置 `809e2cae…` 未变；词库 `ceb7bf3c…` 随正常学习变化。

## 待用户复验

- 生产输入源下按一次 Shift：应弹出中文/英文 HUD；
- 打开更新窗口：检查前后不再出现空进度条，下载时显示进度；
- 若 HUD 仍不出现，请说明使用的应用与光标位置（HUD 需要有效插入点）。

## 证据

`docs/reviews/163-v014-evidence/00-install.txt`。
