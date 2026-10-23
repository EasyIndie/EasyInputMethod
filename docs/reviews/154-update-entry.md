# 154 输入法菜单「检查更新…」入口（ADR-273）

## 变更

- 输入法菜单分隔线后新增 **「检查更新…」**（无快捷键）：
  - 若已安装独立更新程序（bundle id `cn.jokerhub.Lampyris.WebsiteUpdateCheck`，位于 `~/Applications` 或 `/Applications`），
    以 `--ui` 启动；
  - 否则用 `NSWorkspace` 打开 GitHub Releases 页面。
- 输入法宿主仍**零网络**：只通过 LaunchServices 拉起进程/浏览器，不发请求、不读取输入内容。
- 预览菜单（`PreviewInputMenu`）同步新增该项与回调，保持生产/预览一致。

## 验证

| 项 | 结果 |
|---|---|
| 控制器菜单 | 9 项（5 状态行 + 分隔 + 检查更新 + 设置 + 关于）；检查更新无快捷键；设置/关于快捷键仍 ⌥, / ⌥A |
| 预览菜单 | 9 项；更新/设置/关于分别路由到各自回调一次 |
| 预览冒烟 | `dev-preview.sh --smoke-test` 通过 |
| 零网络 | 宿主只调用 `NSWorkspace`；`make verify-no-network` 仍通过 |

## 边界

- 更新程序尚未随 Release 分发，因此当前点击只会打开 Releases 页面；随包分发需要单独签名/公证与体积评估（后续）。
- 生产已装 v0.1.0 不含该入口；下一次候选包（build8）才会带上。
