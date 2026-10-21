# T-ITER-24：组合中方向键候选浏览与预编辑保护

- 状态：用户实测反馈方向键仍有乱码，发布阻断保持；ADR-232已修复预览遗漏的组合导航保护，实际适配器回归修复前失败/修复后通过；待用户重开新预览复验及新签名候选原生复验。
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
- Computer Use重试后绑定已构建`LampyrisPreview.app`并观察：输入`wq`出现组合候选；按↓后组合仍为`wq`，未误提交；按空格后宿主文本为第二候选“像”，组合清空。确认预览路径方向导航及按焦点提交行为，但浮动候选面板不在截图/AX树中，未直接观察焦点高亮或列表。
- 直接启动独立预览包绕过`make macos-dev`隔离包装器，导致真实个人词库短暂新增主动选择学习行`wubi / wqje / 像 / 1`。已通过既有FFI删除API仅删除此行；词库恢复测试前SHA `74f76e92a6cab0eb312d73a4eec575e8d17a9d919a47630bbde0a2f827da7137`（492字节），config SHA `3bc1117cc3379a4c6a100bc6d2cf3ddd3bfa37a25739437a32087a87935c7550`未变。开发工作流已补充禁止直接启动构建产物的隔离边界。
- 新包/安装包未重建或替换；候选可见性、高亮、数字/鼠标直选及真实 IMK 原生结果仍未验证。正式发布阻断继续保持。

### ADR-232 用户反馈后修正（2026-10-21）

- 用户确认预览输入区←→乱码、↑↓可浏览，并提出横排应使用←→；该反馈覆盖此前仅↓/空格的局部通过结论，不能宣称方向键整体可用。
- 源码复现确认：`PreviewInput.keyDown`仅拦截↑↓，未调用正式IMK控制器已有的`consumesCompositionNavigation`；←→会把AppKit专用字符送入字符路径。新增实际适配器回归在原实现以`keyCode=123`失败；补齐共享导航保护后，7键×3种表示（功能键字符/U+001F/空字符串）均保持完整文本和组合，空格确认正确项。原共享函数测试不能发现适配器漏接。
- 修复仅4行预览导航守卫；不变更引擎/词库/配置。严格Swift构建及完整预览冒烟、`make verify`（198产物零网络检查）通过。初次沙箱冒烟exit134，正常权限下修复前exit1、修复后exit0；保留原始日志，不能将沙箱崩溃归因为本产品运行缺陷。
- 证据：`platforms/macos/build/acceptance-arrow-232/`的`before.log`、`after.log`、`build.log`、`verify.log`和`source.diff`。系统IMK安装包未换；用户物理键复验与同SHA系统IMK验收仍待，不关闭发布阻断。
