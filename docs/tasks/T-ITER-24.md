# T-ITER-24：组合中方向键导致控制字符上屏

- 状态：修复已实现且本地验证通过；新签名候选原生复验待推进（发布阻塞保持）
- 优先级：P0，关闭前不得认定最终产品验收通过。
- 复现：自有TextEdit空白文档，混输输入wq，依次↓、↑、空格。未得到你；定向复查输出空格与U+001F（不可见控制字符）。
- 已知：原源/完整启用集合恢复，真实配置/词库不变，自有文档关闭。非扩大操作或用户窗口干扰。方向键选词尚无既定约定，但不应向正文插入控制字符；不能仅按不支持选词关闭问题。
- 定位入口：InputController.handle事件的physical keyCode/charactersIgnoringModifiers，未处理箭头后交给核心并passThrough的组合状态；需观测受控固定键的事件映射，不记录用户输入。
- 修复约束：先ADR明确组合中导航与客户端动作契约，避免顺手增加候选选中功能。回归覆盖四方向及与空格/数字/退格/Esc交互，预编辑/提交同步且不丢字、重复提交或控制字符污染。
- 验收：make verify零诊断、strict宿主构建和离线回归；重新签名候选及自有文档原生复验。不得改写已安装签名资源。
- 证据：/private/tmp/lampyris-final-product-B-20261013/textedit-arrows-btfbxnre及textedit-arrows-_v2pmiry，后者test-output.txt只含测试文本；summary.json。

## 修复实现

ADR-151：宿主按物理键消费组合中的四方向，保持引擎/marked text，不新增候选导航。真实NSEvent+FFI回归覆盖四方向、Shift、命令修饰、三种字符表示及退格/Esc/数字/空格。make verify、离线平台门禁、隔离预览和strict universal通过；已装d429cec未改动，不能以预览关闭发布阻塞。
