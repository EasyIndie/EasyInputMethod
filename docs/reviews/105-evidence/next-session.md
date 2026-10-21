# 下一会话提示词

状态：EasyIndie/EasyInputMethod，产品源码main 3728dfc，PR #54已四门禁通过合入；当前文档分支docs/mvp-input-rc-evidence。实现提交915a70a/8e35700/323b1a1。读AGENTS→HANDOFF→报告105，旧候选8eb872f的报告104结果不能继承。

任务：3728dfc正式/隔离包已核验，B隔离实体已安装注册；等待用户在系统设置添加“萤火虫隔离验收 dce4ae25”，再B→A隔离原生复验；不创建tag/Release。

步骤：
1. git fetch origin、git status，读HANDOFF与105最后的签名候选状态。实际启用列表可用私有根内tissrc list读取；不能把全注册元数据enabled标记当实际启用。当前ABC。
2. 正式39520979475、隔离39521162723均成功且本机签名/票据/Gatekeeper通过，完整zip/执行SHA见105-evidence/*package-identity.json。B根dce4ae25完整路径见isolated-target.json；未启用，不重复出包。
3. 已装B生产执行535d546f9de10541498e123dbb99fde078d37ebe1f2291dc52da8b008a7b1420；config3bc1117cc3379a4c6a100bc6d2cf3ddd3bfa37a25739437a32087a87935c7550；词库74f76e92a6cab0eb312d73a4eec575e8d17a9d919a47630bbde0a2f827da7137。本轮已有只读精确API和实际列表确认ABC；恢复必须以每批实时基线为准。
4. 按iterate-macos-ime及现有所有权/焦点/恢复协议，仅自有窗口验证单字同码/主动生僻字/退格/翻页/重启/三模式/数字提交及七词。随后定位宿主预编辑回写、候选布局与窗口更新，16ms/30MB门槛不变。
5. 同包A/B、应用与安装升级保留/恢复卸载、独立重建与零外联完成后才锁RC开始五工作日。写报告105后续证据，更新HANDOFF/任务卡；make verify后走PR。

边界：不改真实配置/词库，不清空学习；只经ime-config持久化。微信仅安全草稿手工验收；不向真实聊天自动发键。不要重复要求录屏或睡眠来补旧候选；先解决具体执行链。433项含292训练、69探索、72冻结后保留，不拿保留集补词再称其独立。开发ad-hoc包未安装；新公证隔离实体已安装注册但未实际启用，生产包未换。
