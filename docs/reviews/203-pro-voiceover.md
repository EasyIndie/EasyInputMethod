# 203 VoiceOver 朗读候选窗（pro，协助实测）

## 1. 目的

「VoiceOver 实读」原本整项记人工。本轮把它拆成两半：**能自动化的客观部分**（候选窗向辅助技术暴露了什么、变化时有没有发通知）由探针取证，**只能人判的部分**（VO 到底念不念、念得对不对）由用户在旁听并回报。用户当场配合完成。

环境：pro（Intel / macOS 13.7.8），0.1.13/build 21，执行 SHA `c3b533e4…`，输入源 `Lampyris.default`，客户端为「文本编辑」。

## 2. 做法

1. `open /System/Library/CoreServices/VoiceOver.app` 打开 VoiceOver（此前是关闭状态，`pgrep -x VoiceOver` 无进程）；
2. 在文本编辑里键入 `wq`（候选面板 17 页、7 个候选/页）；
3. 用户听并回报**三个时点**：弹出候选面板、按 → 切到第 2 个候选、按空格上屏；
4. 同时用新探针取证：`axdump`（候选窗 AX 树）、`axobserve`（AXObserver 记录通知）；
5. 结束后关闭 VoiceOver、清空文档、输入源还原 ABC。

为此新增/扩展了探针：

| 探针 | 说明 |
|---|---|
| `axdump [bundleID] [depth]` | 递归打印 AX 角色/描述/值，判断辅助技术能读到什么 |
| `axobserve [bundleID] [秒]` | 注册 AXObserver，记录通知（含 `AXAnnouncementRequested`），判断变化时会不会告诉辅助技术 |
| `keytopid` 命名键 | 新增 `left/right/up/down/esc/tab/return/delete/space`；**坑**：之前直接写 `right` 会被当成字母 r-i-g-h-t 打进去（`keytopid` 原来只认单字符） |

## 3. 用户实测结果

| 时点 | VoiceOver 表现 |
|---|---|
| 弹出候选面板（`wq`） | **念了**，内容为「输入编码 wq」 |
| 按 → 切到第 2 个候选 | **不念**新候选 |
| 按空格上屏 | **不念**上屏结果 |

## 4. 客观取证

### 4.1 候选窗暴露的 AX 信息（够 VO 念）

```
AXWindow(AXSystemDialog)
  输入编码            AXStaticText  value=wq
  第1页，共17页        AXStaticText  value=1/17
  ←→浏览 · 空格确认 · 数字直选
  输入模式：混输 / 语言：中文 / 宽度：半角 / 字形：简体 / 标点：中文标点
  上一页 [AXButton] 下一页 [AXButton]
  AXScrollArea
    第1项，你，五笔，键盘焦点，首选  [AXButton] value=1 你
    第2项，像，五笔                   [AXButton] value=2 像
    …
  完整码 WQIY   Y识别码：点/左右   AXStaticText
  亻，键W / ⺈，键Q / 小，键I        AXGroup
```

即：候选文字、来源（五笔/拼）、序号、页码、当前选中项（描述里带「键盘焦点」「首选」）都暴露了，信息量足以朗读。

### 4.2 通知行为（`axobserve` 记录）

- 弹出/重建面板：一串 `AXValueChanged`（`输入编码`、`第1页，共17页`、提示行）+ `AXCreated`（面板窗口）→ 这就是 VO 能念出「输入编码 wq」的原因。
- **按 → 换候选：没有任何通知**（候选按钮的 `AXDescription` 从「第1项…键盘焦点，首选」静默变成「第1项…首选」/「第2项…键盘焦点」，但既不 `AXValueChanged` 也不 `AXSelectedChildrenChanged`/`AXFocusedUIElementChanged`）。
- 上屏：输入法侧无通知（文档文本变化属于客户端 App 自己的 AX 事件）。
- 全程没有 `AXAnnouncementRequested`。

**结论**：候选窗的「可读性」没问题，缺的是**选中项变化/上屏时的主动播报**。VO 只在面板创建那一下被值变化带着念了编码，后续选择变化它无从得知。

## 5. 建议（0.1.14，需 ADR）

在候选窗控制器里补两个通知，成本很低：

1. **选中项变化（方向键/数字键/翻页）**：
   `NSAccessibility.post(element: panel, notification: .announcementRequested, userInfo: [.announcement: "第2项，像，五笔", .priority: .medium])`；
   顺带把选中项暴露成面板的 `AXSelectedChildren`，并 post `.selectedChildrenChanged`，让 VO 能自己浏览候选列表。
2. **上屏（空格/数字直选/标点自动上屏）**：可选地播报提交文本（如「你，已上屏」），至少保证不打断后续输入。

两条都只影响辅助技术通道，不改变可见 UI 与键处理；建议连同 `install.sh` 的「自动注册输入源」假成功（报告201 §5）一起进 0.1.14。

## 6. 证据与收尾

- 证据：`/tmp/lampyris-vo/candidate-tree.json`（AX 树）、`candidate-visible.png`（面板截图）、`tree3-before.json` / `tree3-after-arrow.json`（选中项迁移）、`ax-events3.json`（通知日志）。
- 收尾：VoiceOver 已关闭（恢复起始状态）、文档已关闭、输入源 ABC、执行 SHA 与 `config.toml` 未变。

## 7. 仍属人工（本轮未做）

物理睡眠/唤醒（`caffeinate -s` 长期阻止睡眠，需先停掉它）、多 Space（非全屏）切换、外接屏热插拔。
