# 160 简化安装与卸载（ADR-276）

## 实测结论（本机 macOS 27）

- `TISRegisterInputSource` 返回 0，包内输入源进入系统已知列表；
- `TISEnableInputSource` 对父源/模式返回 0，**模式随后出现在启用列表**（无需注销）；
- `TISSelectInputSource` 对第三方输入法返回 **-50**，所以“选中”仍必须用户操作一次（⌃Space 或菜单）；
- `TISDisableInputSource` 返回 0，配合删除应用可清理条目。

## 变更

- 新增 `platforms/macos/tools/tis-source.swift`，构建时编译为
  `Lampyris.app/Contents/Helpers/LampyrisTIS`（随 app 签名/公证；`ci-sign.sh` 显式签 helper 后 `--deep --strict` 校验）。
- `install.sh`：安装完成后 `register` + `enable`，提示用 ⌃Space/菜单选中；helper 缺失或失败时回退旧说明。
- `uninstall.sh`：自动 `switch-abc` + `disable`，再移动应用；helper 失败时仍要求 `--input-source-removed`。
- Pages/RELEASE-README 更新为「一条命令安装 → 选一次输入法」「一条命令卸载」。

## 验证

- helper 在本机 `status` 正常读取生产源（不改变当前 Sogou 输入源）；
- 卸载脚本新增两条回归：helper 成功时无需 `--input-source-removed`；helper 失败时仍阻止并提示；
- `make verify`、46 项离线回归通过。

## 边界

- 需要新 Release（0.1.3/build11）才能让用户用到随包 helper；
- 输入源菜单显示名在改名/首装后可能需要一次重新登录才刷新（系统缓存）；
- 首次选中输入法仍需用户一次 ⌃Space/菜单操作，macOS 不允许程序代选第三方输入法。
