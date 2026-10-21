# 108 — 统一开发包换包与验收

2026-10-21，B arm64/macOS27.0.1。用户明确授权合并#61并构建统一开发包；main为594c8c6c03fdfe77ed03e74575ffeb83e02c1ff7。包含ADR-231…236交互修复和ADR-237/D16词库，非正式RC，不创建tag/Release。

## 当前结果

- 公证运行39599835167成功；本机核对zip SHA、源码标记、两核心词表SHA、codesign、Gatekeeper、stapler均通过，完整值见机器证据。
- 固定开发包装器换包成功，执行SHA `5b5ad43c661edde59ca78a06a1cf9186ed55c1e41ac5d9c5e9d917b51990568b`。实际来源为搜狗拼音，换包前后来源及启用集合一致；未通过API选择输入源。配置/个人词库由固定私有根保留，生产config/词库仍为3bc1117c…/74f76e92…。
- 旧包保留在固定根`replacement-hzka_uyd/previous.app`，可用`python3 scripts/macos-imk-dev.py install --app <绝对previous.app路径> --stop-host`按同守卫恢复。
- 同源码正常权限复跑`test-tools-presentation.py`通过（11.941s）；此前剪贴板失败为历史记录，本次无需改代码，不能据此声称完整离线套件通过。
- `test-composition-navigation.py`通过（15.545s），不向桌面发键。

## 待验范围

已请求用户切换已有“萤火虫开发 d4fcecfb”；尚未确认新PID加载或原生输入。切换后先核对精确可执行路径/执行SHA，再在自有文稿验证实际横竖排导航、空格焦点提交、数字直选、学习区同步、Option快捷键和新增词；焦点/身份守卫不通过则停止。不调用已知存在矛盾的程序选源API。

真实IMK候选显示与提交一致性、三模式、丢字/重复提交、宿主性能、A/B兼容、安装升级及五日试用仍待。预览用户通过、工程测试和包级通过分别记录，不跨候选累加。

机器证据：[108-unified-development-evidence.json](108-unified-development-evidence.json)。原始本机日志`/private/tmp/lampyris-108-{install,tools-presentation,navigation}.log`，安装日志持久副本在上述replacement目录installation.json。
