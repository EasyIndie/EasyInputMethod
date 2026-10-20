# 104 — B（arm64 / macOS 27）隔离候选复验

2026-10-20，MacBook-Air / macOS 27.0.1。**arm64-macos27 已转 PASS；当前 pass 12 / fail 0 / skip 0 / blocked 11**。`acceptance-results.py check` 返回预期 BLOCKED（3），格式与证据引用有效；不代表完整发布验收通过。

## 1. 候选与边界

产品候选源码固定为 `8eb872ff9b585d8b769f6fb3784285dcc3d81606`，正式 universal 与独有身份 arm64 隔离包来自同一提交。测试驱动后续兼容修复不改变产品载荷。报告103的f74aae7为历史对照，不继承其PASS；新候选Intel项仍待A机复验。

| 包 | CI run | zip SHA-256 | 执行 SHA-256 |
|---|---|---|---|
| 正式 universal（仅验证，未安装） | 39396417287 | `d5e8f30a4eb8bd6f43b496dee65998c3776fe5634813bf5c47da2fb6b625eccb` | `4e9986578fc30828daf5810335a22800e357dab407a304064af1c8b853c12781` |
| arm64 隔离验收 | 39396425237 | `e719875d5349256f541bb2496e80afaa4005d91207286a71e071c8453a9b71a1` | `8e8df20b901615d9d0e1c61bdcf32a04b81bd50931de190594a1e4e551dd362a` |

正式源码包SHA：`81c5eaa0d5858ed92216dd161ca447a0c6dc7e70f812f593b87b1c4fee0ec0a9`。两包严格签名、Notarized Developer ID、公证票据、实际架构和源码绑定均通过；隔离包另核对TARGET-ROOT/IMKTestRoot及独有UUID。原始身份/核验日志见 `104-evidence/*identity.json`、`formal-verification.txt`、`isolated-install.txt`。

## 2. 设备与数据保护

- 旧生产执行SHA：`535d546f9de10541498e123dbb99fde078d37ebe1f2291dc52da8b008a7b1420`；公证Developer ID包未替换。
- 真实config：1942字节、8个显式快捷键，SHA `3bc1117cc3379a4c6a100bc6d2cf3ddd3bfa37a25739437a32087a87935c7550`。
- 真实词库：492字节、29行，SHA `74f76e92a6cab0eb312d73a4eec575e8d17a9d919a47630bbde0a2f827da7137`。三项从初始基线至收尾逐字节摘要一致。
- 初次采集原源为搜狗拼音；用户随后改为ABC。重启后按实际ABC创建0600 selection journal，各批按此恢复，不覆盖用户新选择。
- 隔离根 `/private/var/folders/z0/1h35x82j7d767_fm_x3tvdsh0000gn/T/lampyris-imk-3b030dda-b3f5-4424-a45c-90c5cfabfbf7`，0700 + 0600 owner；重启被清理后按ADR-131核验公证身份再重建。用户手动添加「萤火虫隔离验收 3b030dda」。配置/词库仅在该根中，归一化测试mode只经ime-config FFI，未手改真实配置。

## 3. 已验证结果及范围

`resource-isolation`、`core-input`、`long-composition`、`undo`、`focus`、`accessibility`、`imk-performance`、`package-validation`、`arm64-macos27`、`application-TextEdit`、`application-Terminal`。

- TextEdit和Terminal各normal/failure/INT/TERM四路径：真实提交“你”、前缀中断恢复、原源与启用集合恢复、真实数据未变；TextEdit另验证预编辑范围及提交后清除，Terminal验证窗口/TTY/PID及TTY恢复。
- 长组合：8字母提交“中国”，20字母组合有界，Esc后恢复；撤销：提交后Command-Z回退为空。
- 候选538×70、HUD94×36均onScreen=true，在屏0，出现时前台为客户端。截图失败使亮暗视觉仍BLOCKED，不以坐标替代图像证据。
- 用户开启VoiceOver后9项AX词项完整，状态切换后客户端保有AXTextArea焦点，源/真实数据恢复。仅覆盖AX朗读面，不宣称完整朗读措辞评审；用户随后关闭VoiceOver。
- **内嵌性能基线**：44按键样本+2面板，total p50/p95/max=13.4/21.2/37.7ms，engine=0.6/1.8/2.2ms；设置/关于57.7/274.7ms。**端到端p95仍超16ms**。imk-performance的PASS只表示基线采样完成，不表示16ms达标；不含IMK dispatch内部与合成器完成。
- `arm64-macos27` 的PASS仅表示同候选在该架构/系统的实际运行覆盖已有充分证据，不替代下表独立功能/应用项目的BLOCKED。

## 4. 阻断与平台差异

| 项 | 原因与边界 |
|---|---|
| `mode-switch` | 中断前模式探针触发TextEdit文档身份/焦点守卫停止，原源和真实数据恢复；不得计通过 |
| `sleep-wake` | 用户手动操作后新的TextEdit输入PASS且源/数据恢复，宿主PID保持3204；pmset只记录21:12息屏/21:18亮屏，当前boot系统睡眠次数仍0，因此不能记完整系统睡眠/唤醒PASS；不再要求用户重复 |
| `light-dark-layout` | B单屏HUD在取亮色截图时screencapture报could not create image from rect；未切至暗色，不以CG窗口坐标代替亮暗视觉证据 |
| `multi-display` | B系统仅识别1块显示器；用户明确本次无第二块屏幕，不执行换屏跟随验收 |
| `intel-macos13` | 新候选 8eb872f 未在 A 机复验；103 的 f74aae7 仅作历史对照 |
| `independent-reproduction` | 需独立第三方复现；CI 自复现不替代独立证据 |
| `one-person-five-days` | 待锁定 RC 后完成五工作日试用 |
| `application-Safari` | 创建独有页面及应用就绪后的有界只读窗口枚举均AppleEvent -1712；未发键，原源/启用集合恢复且真实数据未变。AX窗口集合为空，未继续重试 |
| `application-Chrome` | 按本轮边界不复测；103 记录 Chrome 侧问题，未对新候选宣称通过 |
| `application-VSCode` | 本机未安装Visual Studio Code，open明确报无法找到应用；已在发键前停止并恢复。未安装新软件 |
| `application-WeChat` | 无隔离草稿，按策略不投递按键 |

补充：AX性能矩阵variant首个暖机样本未观察到文本变化而停止，cold/dictionary共享此前置，未盲目重复；不以外部AX等待器数值代替内嵌计时。旧`selsrc`查询为空而新编译source-state可读精确ID；TextEdit 1.21的冷启动、新空白窗口复用、对象销毁/no-result差异按ADR-221处理；VSCode未安装，按ADR-222先补齐逐批输入/保存/关闭守卫，未向未知应用发键。菜单索引、设置默认分区及截图授权归因未取得正式证据，不作平台推断。

工具修复：ADR-219修复TextEdit中断锚点及离线mock/等待替换、性能矩阵旧文案断言；ADR-220/222补齐性能及VSCode逐批守卫。原失败记录全部保留。首次睡前失败是前一状态切换将隔离mode留在pinyin；经ime-config恢复mixed后睡前输入PASS。用户报告手动唤醒后的独立输入也PASS，但系统仅记录息屏/亮屏，故完整睡眠项保持BLOCKED，未再要求重复。

## 5. 收尾与复核

ABC已恢复，非自有启用集合保持。严格按本轮fixture路径查询的文档均已不存在；未操作未知“未命名”窗口。隔离宿主停止前lsof未发现网络socket（单次快照），随后按执行路径核验并停止PID3204。真实执行/config/词库摘要均与基线一致，见 `login1/final-restoration.json`。

用户确认设置已无隔离项后，TIS `includeAllInstalled=false`及激活后的输入菜单均确认隔离源已移除；`includeAllInstalled=true`保留的旧模式enabled标记曾导致误判。已核验身份/执行SHA/strict签名，注销并可逆归档本轮隔离包至`packaging/out/b-8eb872f-retired/`；临时根已由重启清理。恢复项PASS，生产三份SHA再次一致，证据`login1/archive-final.json`。

make verify零诊断通过（含182产物隐私符号检查）；相关离线回归与真实客户端证据见各项记录。正式候选CI已完成完整离线回归、公证与离线重建。当前全部PASS引用文件可由机器报告逐项定位；证据位于 `104-evidence/login1/`，工作目录为 `platforms/macos/build/acceptance-b-104/`（不入库）。

