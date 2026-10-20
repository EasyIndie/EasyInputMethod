# HANDOFF — 当前状态

## 0. 元信息

- 更新：2026-10-20 / Codex（GPT-6）；用户要求继续可验项，同候选补验中，等待录屏权限。
- main基线cbb2b45；产品候选固定8eb872f，ADR-223/224仅修复验收窗口及Safari AX就绪等待。
- 报告104：pass14 / fail0 / blocked9；新增模式循环及Safari四路径PASS，三项性能矩阵已完成。
- 最近门禁以提交前make verify结果为准；本轮TextEdit/Safari离线9/8例通过。

## 1. 设备与数据

| 设备 | 包与系统 | 配置/词库 | 当前来源与恢复 |
|---|---|---|---|
| A（来自15:55交接，非本机回读） | Intel/macOS13.7.8，生产07bbb2f，执行681fb1c8… | config809e2cae…，词库2ee1a469…/217行 | 生产萤火虫；报告103的f74aae7 pass18/blocked5，不继承到新候选 |
| B（21:25回读） | arm64/macOS27.0.1，生产17053e1，执行535d546f9de1…，公证accepted，宿主未运行 | config3bc1117cc337…/1942字节/8显式快捷键；词库74f76e92a6ca…/492字节/29行；全程未变 | 实际本轮原源ABC，已恢复；初始搜狗拼音由用户在登录前改为ABC，不强制改回旧选择 |
| B隔离身份 | 产品源码8eb872f，arm64公证包；zip e719875d…9b71a1，执行8e8df20b…dd362a | 仅私有根，曾由ime-config将VO测试遗留pinyin恢复mixed | 上轮已归档，本轮重新安装并由用户添加；当前宿主PID17067，按批恢复ABC |

- 完整两包zip/执行SHA、CI run、签名与绑定证据见报告104；正式universal包只验证未安装。
- 私有根：`/private/var/folders/z0/1h35x82j7d767_fm_x3tvdsh0000gn/T/lampyris-imk-3b030dda-b3f5-4424-a45c-90c5cfabfbf7`（本轮已重新建立0700+0600 owner及ABC journal）；当前安装包 `~/Library/Input Methods/LampyrisIMKTest-3b030dda-b3f5-4424-a45c-90c5cfabfbf7.app`。

## 2. 本轮结论

- B TextEdit/Terminal各四路径、长组合/撤销、VoiceOver AX面/焦点、候选/HUD在屏及核心输入PASS；arm64平台运行覆盖PASS。
- 内嵌trace44按键+2面板：total p50/p95/max=13.4/21.2/37.7ms，engine=0.6/1.8/2.2ms，设置/关于57.7/274.7ms；仅基线PASS，端到端p95仍超16ms。
- 用户报告手动唤醒后的TextEdit输入PASS；系统仅记录21:12息屏/21:18亮屏、当前boot Sleep/Wakes=0，故完整系统睡眠项仍BLOCKED，不再重复要求用户睡眠。
- 归属可由本轮fixture路径证明的文档均已不存在；未关闭未知“未命名”窗口。真实执行/config/词库摘要一致，详细原始证据见104-evidence/login1。

## 3. 未决

- 上一轮收尾完成；本轮用户要求继续，已恢复同包与私有根，用户重新添加源。当前按批恢复ABC，最终移除/归档待补验完成后进行。
- B阻断：VSCode未安装；录屏预检false、亮暗截图待用户授权；无第二屏；系统睡眠无正式事件。宿主15提交基线在新窗口创建守卫停止，未盲目重试；三项AX矩阵已通过。
- 跨设备/发布阻断：8eb872f的A机复验、独立第三方、五工作日、Chrome已知外部问题、WeChat按策略不发键。
- 产品端到端p95是否优化仍需另立ADR；不以基线采集PASS等同16ms达标。未关闭IT-12、UI04或MVP。

## 4. 下一步（断点）

1. 用户要求继续后，录屏预检与官方请求API均false；已请求用户开启TCC，尚未确认。原外观暗色，ADR-225已修复探针显式亮色起点/退出恢复；授权true后跑单屏run-installed-hud-probe.py，不重复已PASS批次。
2. 本轮私有根与已装隔离包恢复为报告104原路径，selection journal0600原源ABC；所有按键仍需精确身份/焦点/源守卫。
3. 补验结束后按TIS includeAllInstalled=false及激活菜单确认移除；不要把全部已注册列表旧模式enabled误作有效启用。还原并归档，再更新报告、make verify、提交推送。

## 5. 边界

- 核心离线/零遥测；配置只经ime-config；不改真实数据、UserDefaults或HIToolbox。
- 仅自有窗口/文档，每批身份/焦点/源守卫；失败停止保留证据，不为PASS放宽判定。
- 不自动注销/重启/解锁；TCC由用户点选；睡眠未证实就保留BLOCKED。VoiceOver用户已关闭。
- 生产包未替换；归档副本在packaging/out/b-8eb872f-retired，本轮另恢复安装副本及私有根以补验。完整身份与平台差异只放报告104。

## 9. 会话日志

- 2026-10-20 / Codex：继续后录屏预检和官方请求均false，未截图或发键，等待用户TCC授权。发现原外观暗色会让探针两张图均暗色，ADR-225显式亮色起点并沿用trap恢复；HUD专项7例通过，报告14/9不变。

- 2026-10-20 / Codex：继续可验项，恢复同公证包及隔离根，用户重新添加源；ADR-223/224修复激活/窗口与AX文本框就绪，模式循环及Safari四路径PASS。简繁/冷启动/1万条词库AX矩阵PASS，宿主基线创建守卫停止；录屏预检false待授权，报告14/9，真实数据未变。

- 2026-10-20 / Codex：用户确认设置已无隔离项，TIS实际启用列表及激活菜单均无隔离身份；此前全部已注册列表的旧enabled标记导致误判。核验签名/执行身份后注销并归档隔离包，临时根重启已清理，生产三摘要不变；恢复项PASS，104现pass12/blocked11。

- 2026-10-20 / Codex：用户再次重启后，独立只读TIS仍报隔离.default启用；ABC、两宿主无进程、生产执行/config/词库SHA全同。临时根已被系统清理，已装隔离包保留，state-restoration继续BLOCKED，证据login1/post-reboot-restoration.json。

- 2026-10-20 / Codex：用户报告手动唤醒后的输入PASS，但系统只有息屏/亮屏事件、当前boot睡眠计数0，完整睡眠保持BLOCKED。ABC/真实数据已恢复，隔离宿主停止、无socket；TIS停用仅父源生效，等待用户系统设置移除隔离模式后归档。104现pass11/blocked12，arm64项PASS。

- 2026-10-20 / Codex：用户授权睡眠验收；首轮被隔离pinyin前置阻断，经ime-config仅恢复私有mode=mixed后睡前PASS。自动睡眠请求后系统当前boot仍0次睡眠，复验守卫停止，均恢复ABC/真实数据不变；已请求用户手动睡眠并唤醒后核验，当前sleep-wake仍BLOCKED（104）。

- 2026-10-20 / Codex：用户开启VoiceOver后无障碍探针PASS（完整AX面/焦点/原源与真实数据恢复）；报告104现pass10/blocked13。已提示关闭VO、保存工作，等待用户确认开始一次睡眠唤醒；尚未执行睡眠。

- 2026-10-20 / Codex：B重启后源可用，私有根重建/ABC恢复journal已建；TextEdit/Terminal四路径及长组合/撤销PASS，内嵌trace44样本total13.4/21.2ms、engine0.6/1.8ms（p50/p95）。TextEdit冷启动与窗口复用兼容按ADR-221修复；VSCode逐批守卫ADR-222本地回归9例通过但应用未装；单屏HUD截图BLOCKED（几何在屏），矩阵AX等待BLOCKED；报告104现pass10/blocked13，arm64项PASS。VO/睡眠待用户配合；修改与证据已落盘，真实数据摘要未变。
