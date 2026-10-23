# 158 检查更新快捷键 + 更新程序静态链接（ADR-275）

## 修复

1. **v0.1.1 更新程序在别的机器上启动崩溃**：`LampyrisUpdateCheck` 动态链接了
   `/Users/runner/work/.../target/release/deps/libime_ffi.dylib`（构建机绝对路径）。
   改为把 `libime_ffi.a` 作为链接输入（与输入法宿主一致）；`otool -L` 已无 `libime_ffi.dylib`，
   本地启动窗口正常。
2. **菜单找不到更新程序**：`UpdateEntry` 改为优先 `NSWorkspace.urlForApplication(withBundleIdentifier:)`，
   再回退 `~/Applications` / `/Applications` 固定路径。
3. **新增快捷键** `hotkey.open_update`（默认 `alt+g`，none 关闭）：
   - Schema/设置「快捷键」分区自动出现；
   - 菜单「检查更新…」右侧显示该快捷键；
   - 控制器按键路径与菜单点击调用同一 `UpdateEntry.open()`。

## 验证

| 项 | 结果 |
|---|---|
| 配置 | 22 项 schema；`hotkey.open_update` 默认 alt+g，冲突/非法值沿用既有校验 |
| 设置 | 22 行、5 分区，快捷键分区含新项；亮暗/最小窗快照通过 |
| 菜单 | 控制器/预览 9 项，更新项显示 `⌥G`，路由仍正确 |
| 更新程序 | 静态链接（无 dylib/绝对 rpath），`--ui` 窗口可打开 |
| 预览冒烟 | 通过 |

## 后续

- 用 v0.1.2 重新构建并发布主包与更新程序；v0.1.1 的更新程序资产为坏包，计划移除。
- 菜单点击/快捷键的真实交互需在新候选上实测。
