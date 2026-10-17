# 报告048：正式控制器模式同步与关于页修正

## 已实现

关于窗口标题改为“关于”；按钮按原生收起标题尺寸整体居中，反馈按钮居中对齐，不让最长子菜单标题撑宽；复制成功提示精确为“诊断信息已复制”（ADR-198）。亮暗离屏真实控件及命名私有剪贴板验证通过。

真实IMKServer/控制器的私有探针复现：先选择五笔、停用，在私有配置改拼音，再激活，旧实现持久配置pinyin而菜单仍五笔。激活时通过既有configChanged统一同步mode和候选配置后通过；新回归直接调用真实控制器doCommand，覆盖父项循环、三子项及两次停用后重激活（ADR-199）。未注册探针或切换系统输入源。

## 验证与未通过项

make verify零诊断全绿，176产物隐私断言通过；严格arm64+x86_64生产构建通过。test-controller-menu、test-tools-presentation、test-input-menu、test-preview-menu定向验证均通过。

随后全量离线回归中，test-preview-menu的现用数据保护断言失败：测试前后真实user-dictionary.tsv摘要不同、config摘要相同。失败保留，不将定向PASS代替整套结果、不归因为已确认的用户并发输入，不写回或恢复未知词库变化。本轮没有测试词提交操作，私有探针使用独立config路径；后续用CI隔离账号核验。原始日志/summary在build/rc-ui-20261017，原始失败目录也保留。

## 正式系统菜单继续待修/待验

用户截图显示IMK代理采用“输入模式：混输”标题回退，自定义view未传到显示层。此前模拟Owner、NSMenu.copy及独立预览不能证明系统代理行为。本轮没有重复已撤回的keyEquivalent/tab布局方案，也未声称右对齐、父项点击保持打开或截图中固定混输的全部原因已解决。已复现并修正的是重新激活时的旧会话模式问题。

本轮尚未收到设备B当前空闲答复；已安装abdb83f宿主正在运行，未替换正式包、未切源或发键。后续须实机观察代理字段/动作与新签名候选验证，完整RC-UI-01保持未完成。正式验收仍沿用1PASS/22BLOCKED。

协议依据：[Apple IMKInputController命令分发](https://developer.apple.com/documentation/inputmethodkit/imkinputcontroller/docommand(by:command:))；原生文档说明命令携带菜单项及客户端字典，默认按selector派发。这里的本地IMK探针通过不能替代跨进程状态栏代理通过。
