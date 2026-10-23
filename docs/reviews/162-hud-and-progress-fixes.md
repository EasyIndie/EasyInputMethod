# 162 验收修复：Shift 切换 HUD + 更新窗口进度条

## 问题

1. 单独 Shift 切换中英无 HUD：`flagsChanged` 路径只清组合/隐藏候选窗，没有走 `showStateFeedback`；
   菜单点击「英文输入」有 HUD，键盘路径缺失。
2. 更新窗口进度条异常：检查前后都显示一条几乎为空的进度条（截图），完成后也无明确状态。

## 修复

- `InputController.handle` 的 `flagsChanged` 分支：Shift 切换成功后调用
  `showStateFeedback(StateFeedback.language(session.isEnglish))`（与菜单同一路径）。
- `UpdateWindow` 进度条状态机：
  - 初始隐藏；检查/空闲/完成/失败时隐藏；
  - 下载开始显示、`doubleValue` 按字节更新；
  - 安装阶段不再复用同一进度条显示不确定动画，避免残留。

## 验证

- 更新程序 22 项 XCTest、严格并发构建、`build.py` 通过；
- `make verify`、46 项离线回归通过；
- Shift HUD 的实机确认需新一轮候选（0.1.4/build12）安装后，在文本框按 Shift 观察；
- 进度条可用更新窗口检查一次（已装旧程序仍为旧 UI）。

## 边界

- HUD 仍依赖有效光标矩形；无客户端/无插入点不显示。
- 只改提示与展示，不改输入、下载、验签与安装逻辑。
