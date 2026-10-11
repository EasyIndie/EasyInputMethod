# macOS 真机测试脚本

无头/人工验收与回归时复用。运行前提：**图形登录会话** + 运行终端已获
**系统设置 → 隐私与安全性 → 辅助功能**授权 + 萤火虫已安装并在输入源里启用。

## 组件

| 文件 | 作用 |
|---|---|
| `imk-auto.swift` | 通用辅助工具（AX 查找/设置/点击、鼠标事件、输入源选择、IME 菜单），脚本运行时用 `swiftc` 编译 |
| `lib-imk-auto.sh` | 共享 bash 函数（编译工具、按键/输入、剪贴板读字段、断言） |
| `im-select.swift` | 仅选中萤火虫输入源（`run-imk-acceptance.sh` 用） |

## 脚本

| 脚本 | 覆盖 | 期望 |
|---|---|---|
| `run-imk-acceptance.sh` | ①②③④⑤⑥⑪⑫ + 状态徽标 / 选字 / Esc（TextEdit、真机 IMK 层） | 默认 `pass=14 fail=0`；`PERF+RESTART=1` 时 `16/16` |
| `run-panel-acceptance.sh` | **⑦ 用户词库 / ⑧ 导入导出 / ⑨ 拼音反查**（AX 自动点击面板） | `pass=7 fail=0` |
| `run-input-apps.sh` | **⑩ TextEdit / Safari / Chrome / Terminal / 微信**输入（合成按键 + 剪贴板） | `pass=6 fail=0` |
| `run-perf.sh` | ⑪ 引擎按键时延（release 探针） | p95 < 16 ms |
| `run-ffi-smoke.sh` / `run-repro.sh` / `test-install.py` / `render_perf.sh` | FFI 冒烟 / 离线复现 / 安装包校验 / 渲染性能 | — |

## 约定与已知边界

- **不热杀宿主**：`killall Lampyris` 后需重启客户端（退出重开文本 App）或重选输入源才能恢复，
  这是已知坑（见 `HANDOFF.md` §6）；本目录的脚本默认不杀宿主。
- 面板脚本会**临时新增一个测试词**（`lpys` / `面板验收词`）并在退出时**还原词库文件**；
  内存态会残留在宿主进程里，直到宿主下次自然重启。
- 不暴露 AX 的 App（**微信**、浏览器地址栏）改用「**合成按键 + 剪贴板**」核验，且**绝不按回车**（避免误发送）。
- 所有脚本结束时自动关闭自己新建的窗口/文档，尽量不干扰用户现场。
- 零诊断门禁：`imk-auto.swift` 用 `-warnings-as-errors` 编译。

## 典型用法

```sh
# 自动验收（TextEdit）
./platforms/macos/tests/run-imk-acceptance.sh
IMK_ACCEPTANCE_PERF=1 IMK_ACCEPTANCE_RESTART=1 ./platforms/macos/tests/run-imk-acceptance.sh

# 面板 ⑦⑧⑨
./platforms/macos/tests/run-panel-acceptance.sh

# 五应用 ⑩（微信需先登录）
./platforms/macos/tests/run-input-apps.sh
```

> 亮/暗主题（⑬）不在本目录：由预览冒烟 `./platforms/macos/dev-preview.sh --smoke-test`
> 在进程内离屏渲染候选窗与设置面板、断言 WCAG 对比度 ≥ 4.5。
