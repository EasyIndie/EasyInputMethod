# T-ITER-24：组合中方向键候选浏览与预编辑保护

- 状态：方向键预编辑保护及上下键候选浏览已实现；定向候选测试、Preview strict build、IMK controller 集成回归和 `make verify` 通过；新签名候选原生复验待推进（发布阻塞保持）
- 优先级：P0，关闭前不得认定最终产品验收通过。
- 复现：自有TextEdit空白文档，混输输入wq，依次↓、↑、空格。未得到你；定向复查输出空格与U+001F（不可见控制字符）。
- 已知：原源/完整启用集合恢复，真实配置/词库不变，自有文档关闭。非扩大操作或用户窗口干扰。ADR-151先消费方向键以保护marked text；现按ADR-231明确上/下浏览当前页，空格确认，边界停留，数字/鼠标继续立即提交。
- 定位入口：InputController.handle事件的physical keyCode/charactersIgnoringModifiers，未处理箭头后交给核心并passThrough的组合状态；需观测受控固定键的事件映射，不记录用户输入。
- 修复约束：方向键不再送入字符引擎或客户端。上下只移动临时候选焦点；翻页后首项聚焦；编辑/取消/提交/失焦清除焦点。左右与Home/End/Delete仍只消费，不增加编辑语义。回归覆盖导航边界、翻页、焦点重置以及与空格/数字/退格/Esc交互，提交不得错项、丢字、重复或污染控制字符。
- 验收：make verify零诊断、strict宿主构建和离线回归；重新签名候选及自有文档原生复验。不得改写已安装签名资源。
- 证据：/private/tmp/lampyris-final-product-B-20261013/textedit-arrows-btfbxnre及textedit-arrows-_v2pmiry，后者test-output.txt只含测试文本；summary.json。

## 修复实现

ADR-151：宿主按物理键消费组合中的四方向，保持引擎/marked text；真实NSEvent+FFI回归覆盖四方向、Shift、命令修饰、三种字符表示及退格/Esc/数字/空格。旧产品包d429cec未改动，不能以预览关闭发布阻塞。

### ADR-231 候选浏览实现（2026-10-21）

- 组合态上/下物理键移动当前页键盘焦点，停在页边界；候选窗高亮焦点并显示“↑↓浏览 · 空格确认 · 数字直选”。空格按焦点索引调用当前页候选选择；翻页后回首项。数字和鼠标直选，方向键不送入字符引擎/文本客户端。
- `test-candidate-presentation.py`通过：导航边界、空列表重置、焦点高亮/AX 标签、焦点索引1确认对应当前页第二项；`dev-preview.sh --build-only` warnings-as-errors 构建通过；`test-controller-menu.py`正常权限复跑通过；`make verify`全绿。
- `make macos-offline-tests`本轮完整运行仍以1项失败结束：`test-tools-presentation.py`在命名私有剪贴板断言“private copy”失败；将输出目录改到全新`/private/tmp`后仍可复现，作为独立离线回归问题跟进。另两项首次失败分别为 controller 进程异常退出和 Swift ModuleCache 沙箱权限；正常权限独立复跑均通过。不得将离线套件记全绿。
- Computer Use尝试打开已构建预览时服务端超时（首次`timeoutReached`，随后`-10005`）；应用清单显示LampyrisPreview处于运行态，但AX不可读，未发任何测试键。预览构建和离屏回归不冒充真实可视交互。
- 新包/安装包未重建或替换；候选可见性/箭头浏览/焦点高亮/空格确认的真实 IMK 原生结果未验证。正式发布阻断继续保持。
