# 113 — 双高亮修复开发包换入与手工复验

2026-10-21，B arm64/macOS27。按用户明确授权合并#63（af2c026）及#65（ef566cd），#65仅ADR/HANDOFF冲突保留两边决策后重新make verify及四CI通过才合并。主线ef566cd9a09f2e0353a4eb9600a88d7237235545，公证运行39617559248。未合并更新原型#64或独立性能#66，无tag/Release。

## 当前包级结果

- zip `c83802d2ad634273943efdbb9ff8a44b8fd8fcdca8b5c6d34757d549f24ce960`；执行 `8f479eb8452397a1307f2205c8095b9da5b3c735517e367830b5d6b84a1ab242`。
- 本机源码标记、词表SHA、codesign、Gatekeeper及stapler均通过；固定身份包装器再次验证Team ID/开发根绑定及完整输入源声明。
- 用户先结束组合切ABC，API也回读ABC。换包前后来源及启用集合相同，旧包在固定私有根`replacement-wcggaewq/previous.app`；安装结果不等于新宿主已加载或原生通过。
- 换包前后私有及生产config.toml/user-dictionary.tsv共四项SHA完全相同，完整值见机器证据。原生产应用未替换。私有mode=mixed（保留用户状态，不重置）。

## 原生复验断点

打开并保留唯一空白TextEdit文稿`platforms/macos/build/manual-113-cbuu_ddr/萤火虫手工验收-113.txt`，窗口2221；原用户手工窗口1902不触碰。已请求用户切已有开发源，输入wq、鼠标停另一候选、按实际布局提示方向键浏览及空格确认；期望只有键盘焦点填充、非焦点hover描边，空格提交焦点项。只读lsof/ps已确认新PID82516持有精确安装执行路径，但当前来源仍ABC，不能当作客户端绑定通过。尚未收到手工结果，不计为原生PASS。

旧594c8c6用户确认过候选窗/方向键/模式切换，但发现双高亮；该历史反馈不直接替代本修复新包验收。候选与数字/鼠标提交逐项一致、常用词/编辑路径、真实宿主16ms、目标A/B兼容、正式升级恢复/独立核验/五日仍按既有出口推进。本次未启用新计时标记，未给真实聊天自动发键。

## 独立性能工作

[PR #66](https://github.com/EasyIndie/EasyInputMethod/pull/66)仅对五项相同状态跳过重复芯片布局；已对齐ef566cd并保留全部离屏补测波动，源码仅三行差异。AppKit回归、strict构建及make verify通过，CI待完成；未合并，不在本包内。离屏局部节省不等于整体16ms达标，不扩展更新功能。实验见该PR报告112。

证据：[113-native-highlight-evidence.json](113-native-highlight-evidence.json)。原始安装日志/private/tmp/lampyris-113-install.log及持久备份目录installation.json；公证下载包在packaging/out/run-39617559248（忽略目录）。

本轮验收记录提交前make verify全绿，200项既有产物网络符号门禁通过；仅文档同步，不新增输入行为。
