# 报告050：撤回平台限制推断，复核系统菜单回归

2026-10-17。用户指出此前测试能够切换，要求给出确切理由。撤回“系统菜单不支持，因此必须换菜单承载”的推断，不更改原交互目标。当前仍未取得足以确认根因的完整证据。

## 已完成对照

本轮继续使用B已装abdb83f、PID1569及相同执行文件摘要；独有文档与原始记录位于build/menu-recheck-b-c2a079eb。没有安装、注入宿主或改动产品代码。

1. 补查二级菜单可见性：主菜单AXVisibleChildren=23；精确父项AXPress后，模式子菜单AXVisibleChildren=3、当前混输选中。随后对子项“五笔”使用其暴露的AXPick，API返回0但持久mode仍mixed。它增强了AX路径的复现证据，仍不能等同于正常鼠标事件路径。上轮未记录二级可见性，不应据此作平台结论。
2. 键盘路径无效：CUA绑定TextEdit发送Down后，系统子菜单选中项仍为混输。说明该键没有进入预期菜单导航路径；没有发送Return，不将此计为系统键盘选择失败或产品失败。
3. 顶层带参数回调阳性对照：半角→全角成功，重新打开真实菜单读回“全角输入”；再切回后读回“半角输入”，菜单取消。由此可排除所有带参数selector均不工作的猜测。
4. 发布优化对照：在私有未注册IMKServer/控制器探针中分别使用-O、-O -whole-module-optimization，真实命令派发及重激活回归均通过。已装二进制亦存在chooseWubiMode/toggleWidth的ObjC thunk。此前调试构建测试的覆盖不足值得注意，但回调被发布优化裁掉的猜测未得到支持。
5. 具体实现差异：1621a6d的纯模式父项由AppKit形成submenuAction:/NSMenu、无自定义view；当前共享菜单形成cycleInputMode:/调用方target，同时有customView与submenu。离屏contract探针与源码均确认此差异。这是后续需要A/B的因素，尚未证明它导致代理回传失败，不能直接写成已定位根因。

[Apple setSubmenu文档](https://developer.apple.com/documentation/appkit/nsmenu/setsubmenu(_:for:))说明标准父项动作为submenuAction:；这不等于Apple声明不支持系统输入法子菜单。报告049引用另一项目仅是旁证，不能据此否定用户此前成功观测。

## 尚缺的证据与当前阻塞

- 正常鼠标事件路径与AXPress/AXPick路径是否等价。受控Swift CGEvent探针已只编译，未执行；已向用户明确请求此操作方式授权，并询问此前成功是系统二级菜单、独立预览，还是设置/快捷键。没有把提问或时间流逝当成许可。
- 若鼠标路径也复现，需对标准父项与当前双重职责父项做受控A/B，并区分命令未到达、接收后失败或被后续状态覆盖；未修改/注入已签名宿主，现有证据不能代替命令接收日志。
- CUA随后返回设备已锁屏、自动解锁不可用，已停止一切桌面动作。需要用户手动解锁；本轮空白复核文档仍待关闭，未触碰原未命名窗口。

## 数据与结果边界

锁屏后仅文件摘要审计：config SHA前后均65643c64fcfd6dd548e20b0c949403e7ff1e440dfe1d4abf9585865e86940c7c；词库SHA均1ebe66cdd09fa7c3c0f8379838506708cb2add0e6e8f226769d2e062cdf53f62；mode仍mixed。临时全半角在锁屏前已读回恢复半角、菜单已取消。锁屏后的源/窗口最终核验未执行，明确待解锁，不冒记完整恢复通过。无配置/词库全文备份、无文字提交、无新权限。正式验收不提升。

## 后续受控鼠标对照（用户确认B空闲后）

用户明确授权Swift CGEvent，并确认此前成功入口是系统菜单栏输入法图标的二级菜单。B已解锁。本轮宿主仍为abdb83f/PID1569；配置摘要未变，现用词库在会话间发生变化，旧基线被保护拒绝，随后保留旧证据、建立mouse-round2-before.json新摘要，没有回写或复制词库正文。

- 全局AXFocusedUIElement读取返回-25204，TextEdit自身的焦点读取返回0/AXTextArea。诊断探针仅在前台是精确TextEdit、焦点窗口CFEqual自有文档窗口、焦点元素确属该客户端文本区域时接受客户端焦点；宿主/源/数据校验保留。
- 已打开系统菜单后，模式父项中心CGEvent点击关闭菜单，配置仍mixed。重新打开后，用AX展开确认三项二级菜单可见，再对可见“五笔”精确矩形中心发送CGEvent鼠标移动及配对按下/抬起。菜单关闭，持久mode仍mixed；因此AX点击适配器单独失效不足以解释当前现象。此处是合成鼠标事件对照，不能称为物理鼠标或硬件验收。
- CGPreflightPostEventAccess与AXIsProcessTrusted均true；没有请求新权限。系统日志只取得IMK Menu调用，未提供模式命令接收/写入结果。尚不能区分命令未到、接收后失败或后续覆盖，不能宣称已定位根因。
- 本轮config/词库SHA和完整输入源集合前后相同，mode=mixed；自有menu-test.txt窗口已关闭，原未命名窗口保留；测试指针位置已恢复，无文字输入、无安装。摘要见build/menu-recheck-b-c2a079eb/mouse-round2-result.json及round2-*原始记录。

下一步离线准备两份诊断候选于build/menu-proxy-diagnostics-20261017：current保留当前模型；standard-parent仅使用标准setSubmenu父项并去掉customView。二者均加入标准错误输出的有限模式命令接收/返回及持久/会话状态，排除输入文本、候选、客户端和剪贴板内容；使用-O/-whole-module-optimization/-warnings-as-errors编译，零诊断。仅为本轮诊断，不提交为产品交互改版；均未运行、未注册、未安装、未签名公证。因此前实机授权排除了宿主替换，已明确请求临时运行/替换并恢复正式包的许可，答复前不执行。正式验收维持1PASS/22BLOCKED。

本轮make verify首轮因沙箱无法取得只读Cargo漏洞库锁失败；允许规范命令获取本机锁后重试全绿、零诊断，扫描176个产物。原失败和重试日志均保留在诊断产物目录。当前跟踪变更仅交接/进度/报告，产品源码未改。

## 临时诊断执行与无会话缺陷修复（ADR-201）

用户已明确允许临时替换两份本地候选并恢复原包。恢复源来自已有abdb83f发布产物，执行文件SHA核对一致，codesign深度严格验证通过；没有为此新建安装/配置/词库备份。

本地候选启动后最初没有产品菜单，原签名包恢复后也一度如此。刷新同一输入源注册、重建并激活自建文档会话后可见产品菜单；不能把这段连接准备不足当作父项A/B结果，也不能据此断言ad-hoc签名就是根因。源选择与菜单检查现用同一try/finally取消菜单并还原ABC；一次未带同操作恢复的核验请求被自动审批拒绝，未执行，补齐finally后通过。

随后current候选出现产品菜单但模式父/子项不可用，未通过三项子菜单可见性门禁，没有点击不可用子项。standard-parent诊断日志得到：

```text
MENU_DIAGNOSTIC menu command=other persisted=mixed session=none
MENU_DIAGNOSTIC local parent-enabled=false child-enabled=false responds-wubi=true
```

因此这两份临时诊断没有完成有效的子项鼠标A/B，也没有取得模式命令接收日志；父项形式差异的因果关系仍未证明。不过日志直接确认另一独立缺陷：menu可以在没有文本会话的控制器上调用，现有代码主动禁用所有模式项，而模式命令本已支持通过ime-config先持久化选择。

ADR-201最小修复只放开模式父项、其自定义视图及三种子项；其余四个会话状态项保持原启用条件。真实私有IMK回归先失败于`mode parent enabled before activation`，修复后验证冷控制器子项持久化、父项真实视图accessibilityPerformPress循环、首次激活状态一致和原停用重激活路径通过。菜单组件测试及make verify零诊断通过、176产物无网络符号；临时工具编译时两处语法错误已更正，未冒记首次编译成功。

本轮最终已恢复原正式包abdb83f（PID20605，执行文件SHA仍c4a070…93151），刷新同一输入源注册，codesign深度严格通过；原模式mixed、原输入源ABC及完整启用集合、config/词库摘要均保持，自有文档已关闭，原未命名窗口保留。最后恢复后的新宿主产品菜单尚未再激活复核；此前原签名包一次激活核验为可见，不能替代最后一次菜单/实际输入验收。恢复摘要见build/menu-proxy-diagnostics-20261017/restoration-result.json。修复尚未安装，临时日志与标准父项实验均不进入产品代码。原正式包条目已启用但切换无效及右对齐问题仍待，正式1PASS/22BLOCKED不提升。
