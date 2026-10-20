# HANDOFF — 当前状态

## 0. 元信息

- 更新：2026-10-20 / Codex（GPT-6）；B本轮验收已归档，收尾等待用户移除隔离输入源。
- main基线 `9ac7e9d`；产品候选固定 `8eb872f`，工程修复ADR-219…222已提交（不改变候选载荷）。
- 报告104：**pass11 / fail0 / blocked12**，arm64-macos27已PASS；检查器预期退出3，完整发布门禁仍BLOCKED。
- 最近验证：make verify零诊断通过、182产物隐私检查通过；9ac7e9d的CI/正式包工作流成功。

## 1. 设备与数据

| 设备 | 包与系统 | 配置/词库 | 当前来源与恢复 |
|---|---|---|---|
| A（来自15:55交接，非本机回读） | Intel/macOS13.7.8，生产07bbb2f，执行681fb1c8… | config809e2cae…，词库2ee1a469…/217行 | 生产萤火虫；报告103的f74aae7 pass18/blocked5，不继承到新候选 |
| B（21:25回读） | arm64/macOS27.0.1，生产17053e1，执行535d546f9de1…，公证accepted，宿主未运行 | config3bc1117cc337…/1942字节/8显式快捷键；词库74f76e92a6ca…/492字节/29行；全程未变 | 实际本轮原源ABC，已恢复；初始搜狗拼音由用户在登录前改为ABC，不强制改回旧选择 |
| B隔离身份 | 产品源码8eb872f，arm64公证包；zip e719875d…9b71a1，执行8e8df20b…dd362a | 仅私有根，曾由ime-config将VO测试遗留pinyin恢复mixed | 宿主PID3204已精确停止，lsof无网络socket；父源已禁用但模式仍启用，等待用户设置移除 |

- 完整两包zip/执行SHA、CI run、签名与绑定证据见报告104；正式universal包只验证未安装。
- 私有根：`/private/var/folders/z0/1h35x82j7d767_fm_x3tvdsh0000gn/T/lampyris-imk-3b030dda-b3f5-4424-a45c-90c5cfabfbf7`（0700+0600 owner，ABC selection journal已建）；已装包 `~/Library/Input Methods/LampyrisIMKTest-3b030dda-b3f5-4424-a45c-90c5cfabfbf7.app`。

## 2. 本轮结论

- B TextEdit/Terminal各四路径、长组合/撤销、VoiceOver AX面/焦点、候选/HUD在屏及核心输入PASS；arm64平台运行覆盖PASS。
- 内嵌trace44按键+2面板：total p50/p95/max=13.4/21.2/37.7ms，engine=0.6/1.8/2.2ms，设置/关于57.7/274.7ms；仅基线PASS，端到端p95仍超16ms。
- 用户报告手动唤醒后的TextEdit输入PASS；系统仅记录21:12息屏/21:18亮屏、当前boot Sleep/Wakes=0，故完整系统睡眠项仍BLOCKED，不再重复要求用户睡眠。
- 归属可由本轮fixture路径证明的文档均已不存在；未关闭未知“未命名”窗口。真实执行/config/词库摘要一致，详细原始证据见104-evidence/login1。

## 3. 未决

- **唯一即时人工收尾**：TIS disable-owned返回后模式仍enabled；已请求用户仅移除「萤火虫隔离验收 3b030dda」，保留生产「萤火虫」。等待回复，不能提前移走包/根或宣称清理完成。
- B阻断：Safari AppleEvent-1712；VSCode未安装；mode触发文档/焦点守卫；HUD截图失败、暗色未验；无第二屏（用户明确）；AX性能矩阵首个暖机等待超时，cold/dictionary未重复同一失败前置；系统睡眠无正式事件。
- 跨设备/发布阻断：8eb872f的A机复验、独立第三方、五工作日、Chrome已知外部问题、WeChat按策略不发键。
- 产品端到端p95是否优化仍需另立ADR；不以基线采集PASS等同16ms达标。未关闭IT-12、UI04或MVP。

## 4. 下一步（断点）

1. 用户确认移除后，仍用根内source-state只读state，确认ABC、非自有启用集合不变、自有父/模式均disabled；不要反复调用TISDisable或写HIToolbox。
2. 签名/执行SHA/UUID/根绑定复核后，注销并归档本轮已装隔离包和私有根（仅本任务资源，不动生产包）；回读生产执行/config/词库摘要和宿主PID。
3. 更新104 state-restoration与收尾证据；检查器应无格式/证据错误、无FAIL/SKIP、仍因明确剩余项返回3。make verify后提交推送main。
4. 后续修复/补验按104阻断表逐项立任务；无须重跑已PASS批次，不自动改候选或安装缺失应用。

## 5. 边界

- 核心离线/零遥测；配置只经ime-config；不改真实数据、UserDefaults或HIToolbox。
- 仅自有窗口/文档，每批身份/焦点/源守卫；失败停止保留证据，不为PASS放宽判定。
- 不自动注销/重启/解锁；TCC由用户点选；睡眠未证实就保留BLOCKED。VoiceOver用户已关闭。
- 生产包未替换；隔离包尚保留待用户移除源后归档。完整身份与平台差异只放报告104。

## 9. 会话日志

- 2026-10-20 / Codex：用户报告手动唤醒后的输入PASS，但系统只有息屏/亮屏事件、当前boot睡眠计数0，完整睡眠保持BLOCKED。ABC/真实数据已恢复，隔离宿主停止、无socket；TIS停用仅父源生效，等待用户系统设置移除隔离模式后归档。104现pass11/blocked12，arm64项PASS。

- 2026-10-20 / Codex：用户授权睡眠验收；首轮被隔离pinyin前置阻断，经ime-config仅恢复私有mode=mixed后睡前PASS。自动睡眠请求后系统当前boot仍0次睡眠，复验守卫停止，均恢复ABC/真实数据不变；已请求用户手动睡眠并唤醒后核验，当前sleep-wake仍BLOCKED（104）。

- 2026-10-20 / Codex：用户开启VoiceOver后无障碍探针PASS（完整AX面/焦点/原源与真实数据恢复）；报告104现pass10/blocked13。已提示关闭VO、保存工作，等待用户确认开始一次睡眠唤醒；尚未执行睡眠。

- 2026-10-20 / Codex：B重启后源可用，私有根重建/ABC恢复journal已建；TextEdit/Terminal四路径及长组合/撤销PASS，内嵌trace44样本total13.4/21.2ms、engine0.6/1.8ms（p50/p95）。TextEdit冷启动与窗口复用兼容按ADR-221修复；VSCode逐批守卫ADR-222本地回归9例通过但应用未装；单屏HUD截图BLOCKED（几何在屏），矩阵AX等待BLOCKED；报告104现pass10/blocked13，arm64项PASS。VO/睡眠待用户配合；修改与证据已落盘，真实数据摘要未变。

- 2026-10-20 / Codex：探针修复 `8eb872f` 已推送；同提交 arm64 公证隔离包安装成功（strict/signature/stapler/架构与绑定均通过），等待用户添加独有源/必要时重新登录，未发键。正式 universal 构建已成功；ADR-220 补齐性能逐动作守卫及源检查，相关回归与 make verify 通过。真实执行/config/词库未改，当前源按用户选择保留 ABC；报告 104 与证据已落盘。

- 2026-10-20 / Codex：B 基线已采（macOS 27.0.1 / arm64，生产执行 `535d546f9de1…`、config 8 显式快捷键、词库 29 行、原源搜狗拼音）；未换包/发键。定位正式 CI 的 TextEdit mock 超时及中断锚点失效，ADR-219 最小修复专项 9 例通过；make verify 全绿。报告 104 进行中，矩阵旧文案断言同步修复；远端完整复核后重新锁候选。
