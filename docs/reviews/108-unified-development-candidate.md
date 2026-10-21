# 108 — 统一开发包换包与验收

2026-10-21，B arm64/macOS27.0.1。用户明确授权合并#61并构建统一开发包；main为594c8c6c03fdfe77ed03e74575ffeb83e02c1ff7。包含ADR-231…236交互修复和ADR-237/D16词库，非正式RC，不创建tag/Release。

## 当前结果

- 公证运行39599835167成功；本机核对zip SHA、源码标记、两核心词表SHA、codesign、Gatekeeper、stapler均通过，完整值见机器证据。
- 固定开发包装器换包成功，执行SHA `5b5ad43c661edde59ca78a06a1cf9186ed55c1e41ac5d9c5e9d917b51990568b`。实际来源为搜狗拼音，换包前后来源及启用集合一致；未通过API选择输入源。配置/个人词库由固定私有根保留，生产config/词库仍为3bc1117c…/74f76e92…。
- 旧包保留在固定根`replacement-hzka_uyd/previous.app`，可用`python3 scripts/macos-imk-dev.py install --app <绝对previous.app路径> --stop-host`按同守卫恢复。
- 同源码正常权限复跑`test-tools-presentation.py`通过（11.941s）；此前剪贴板失败为历史记录，本次无需改代码，不能据此声称完整离线套件通过。
- `test-composition-navigation.py`通过（15.545s），不向桌面发键。

## 待验范围

用户已切源并确认新PID7730加载；局部原生结果及未通过项见下文补验。切换后先核对精确可执行路径/执行SHA，再在自有文稿验证实际横竖排导航、空格焦点提交、数字直选、学习区同步、Option快捷键和新增词；焦点/身份守卫不通过则停止。不调用已知存在矛盾的程序选源API。

真实IMK候选显示与提交一致性、三模式、丢字/重复提交、宿主性能、A/B兼容、安装升级及五日试用仍待。预览用户通过、工程测试和包级通过分别记录，不跨候选累加。

机器证据：[108-unified-development-evidence.json](108-unified-development-evidence.json)。原始本机日志`/private/tmp/lampyris-108-{install,tools-presentation,navigation}.log`，安装日志持久副本在上述replacement目录installation.json。

## 用户切源后补验

用户回复已切换后，TIS准确回读开发模式，lsof/ps确认PID7730持有上述精确可执行路径，执行SHA一致。自有TextEdit文稿中`wq+空格`、`wq+1`均为“你”；随后输入wq按Esc保留先前提交文本，自有文稿正常关闭。这是该源码的局部原生观察，不继承其他候选结论。

后续自动化未通过预期：右键/下键后空格均仍提交“你”，数字2读回“wq”；默认Option-M未改变私有mode，huiguiceshi读回原串。去掉组合期文档读取后，方向键/数字2观察不变。实际候选窗布局/焦点视觉未取得，不能断言方向轴错误，也不能将失败默认为脚本问题。已请求用户物理键对照；候选导航、Option快捷键、新词原生输入仍待。测试结束私有mode仍wubi，所有自有文稿关闭，输入源保持用户选择，未调用自动选源。生产两SHA完整值见机器证据。

原始日志`/private/tmp/lampyris-108-native*.log`与自有夹具结果在`platforms/macos/build/acceptance-108/{native,more}.*`；含前置断言失败，不计整批PASS。此前“待用户切源”已完成；下一断点为物理键对照与问题定位。
