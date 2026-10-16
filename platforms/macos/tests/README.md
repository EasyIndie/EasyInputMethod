# macOS 原生与离线验收

当前IT-02独立面板隔离已完成；IT-01真实IMK学习数据隔离、Safari/Terminal协议仍未完成。`run-imk-acceptance.sh`和`run-input-apps.sh`在任何外部命令前BLOCKED/3退出，无绕过参数。不要用旧通过计数宣称最终候选达标。

## 安全入口与范围

日常迭代优先`make macos-dev`：构建并启动下表interactive入口，窗口提供正式InputStateMenu的“输入法菜单”按钮和正式设置面板。每轮私有配置/词库；关闭窗口或终端`close`结束，再次运行重建。菜单/设置/快捷键/模式控件实时同步；不注册输入源，不替换已装包。普通`make macos-preview`使用真实配置，不能当作数据隔离入口。

| 命令 | 实际范围 |
|---|---|
| `run-panel-acceptance.sh --isolation-probe` | 独有配置/词库和子进程，normal/failure/INT/TERM；不代表完整产品UI通过 |
| `run-panel-acceptance.sh --interactive` | 启动唯一身份的隔离应用；原生面板交互单独记录，结束在终端输入close |
| `run-owned-library.py` | 共享TextEdit所有权四路径；不输入、不改输入源 |
| `run-owned-probe.py` | TextEdit唯一文件对象协议双路径，失败保留自身证据 |
| `dev-preview.sh --smoke-test`（上级目录） | 隔离预览/离屏亮暗截图、实际语义颜色合成对比度；不替代VoiceOver或真实IMK |
| `run-perf.sh` | 引擎探针，不能代替IMK宿主延迟/内存/功耗 |

面板测试不备份/覆盖真实词库，也不在已安装进程合成学习；配置通过ime-config初始化到自己的根目录。独立测试应用缺少隔离参数时拒绝启动。正常退出清理自己的PID和目录；超时/异常保留证据，不关闭用户应用。微信尚无安全隔离草稿，不投递按键。剪贴板工具self-test仅使用命名剪贴板，通用剪贴板恢复有跨进程竞争边界，真实环境测试须另有隔离条件。

## 最终覆盖报告（ADR-110/125 / IT-03）

```sh
python3 platforms/macos/tests/acceptance-results.py template /tmp/lampyris-acceptance.json
python3 platforms/macos/tests/acceptance-results.py check /tmp/lampyris-acceptance.json
```

当前报告使用schema 2，试用ID为`one-person-five-days`；旧schema 1报告不用于最新门禁。模板全部BLOCKED，身份留空，不能通过检查；创建采用独占模式，不覆盖既有报告。补实际包SHA-256、40位源码提交、arm64/x86_64、Developer ID公证状态、系统及六应用版本；每个固定必测ID恰好一次。PASS附现存证据文件（相对报告目录或绝对路径），FAIL/SKIP/BLOCKED说明原因。覆盖长组合、撤销、焦点、切换、睡眠、辅助操作、布局、多屏、宿主性能、双架构系统、独立复现、单人五日及六目标应用。

退出码：0本报告覆盖门禁通过；1有效报告含FAIL；2格式/身份/证据/覆盖不完整或必测SKIP；3有效报告存在BLOCKED。失败和阻断并存优先返回1。工具核验声明和证据存在性，不自动证明签名、哈希或证据真实性，最终包核对与独立审核仍由IT-13/14/15执行。缺应用版本、没有环境、仅有FFI结果均不能声称最终产品通过。

## 离线保护回归

```sh
PYTHONDONTWRITEBYTECODE=1 python3 platforms/macos/tests/test-acceptance-results.py
PYTHONDONTWRITEBYTECODE=1 python3 platforms/macos/tests/test-panel-gate.py
PYTHONDONTWRITEBYTECODE=1 python3 platforms/macos/tests/test-owned-resources.py
PYTHONDONTWRITEBYTECODE=1 python3 platforms/macos/tests/test-owned-probe.py
PYTHONDONTWRITEBYTECODE=1 python3 platforms/macos/tests/test-fixture-guard.py
```

原生工具用`swiftc -warnings-as-errors`。已有多机证据见MVP-05及人工验收文档，不替代最新最终签名包。TextEdit实际文档字段为path，无window.document；关闭后可保留隐藏window，判断文档消失/测试窗口不可见及原可见窗口ID保持。

## 独有IMK探针（ADR-115/117）

`isolated-imk.py`创建并构建独有身份、私有配置/词库的临时应用；`run-isolated-imk-probe.py <root>`验证正常/失败/中断及所有权拒绝，不注册输入源。`run-isolated-source-probe.py <root>`仅尝试用户输入法目录内独有软链注册，记录原输入源与启用集合；不启用、选择或发键。成功清理不代表TIS缓存完全删除。设备B首次真实注册BLOCKED，尚未证明系统装载；失败保留资源供所有权复查，勿盲目重跑或批量删除。离线回归：`test-isolated-imk.py`（5项）、`test-isolated-source-probe.py`（6项），mock结果不能充当原生证据。

ADR-118：注册前对独有软链执行有界LaunchServices识别，结果存0600的launchservices-recognition.json；识别失败不调用TIS注册。设备B识别/注销成功而TIS未枚举，权限原因尚未证实。

ADR-119：`run-physical-source-probe.py <root>`仅复制独有实体包进行注册对照，不启动/启用/选择；核对整个文件树并只清理自身包。异常保留证据，不自动替换日常包。`test-physical-source-probe.py`验证文件修改、权限、软链与新增目录保护（3项）；真实两组签名注册仍BLOCKED。

ADR-120/121：最新测试身份为cn.jokerhub.inputmethod.LampyrisIMKTest.<UUID>，原生实体注册已枚举两个身份。实体驱动在注销/删除自己的包后重新核对完整启用集合和独有禁用状态；只看到TISDisable返回0不能判成功。新版完整驱动在设备B已exit0；隔离服务启动READY，真实客户端输入未验。

防止重复踩坑：参阅[IMK标识与注册排错](../README.md#imk包标识与注册排错adr-120122)。实体驱动注册前校验inputmethod命名段、两份模式清单及连接名；必须用完整驱动的最终状态复核结果判断清理成功。

### 已安装隔离包的TextEdit单文档输入

`run-installed-textedit-probe.py <已核验私有根> <source-state helper>`只针对已安装且父源/模式均启用的独有隔离包。先核验身份、绑定和严格签名，以及当前源与恢复日志；创建独占文件，逐键检查输入源、文档/窗口和AX文本焦点，发送wq与空格，检查提交“你”，随后恢复原源并关闭自己的文档。共享动作AppleEvent超时5秒，驱动超时先TERM让清理运行，失败保留文件和result.json。不操作真实配置或剪贴板，不自动抢回用户焦点。原生发键需明确解除此前“只切换、不输入”的约束；用户已批准原生发键；本次运行被TextEdit前台检查拦截，未完成提交断言。原源/完整启用集合及真实数据摘要恢复；System Events只读焦点查询AppleEvent超时，待权限/服务状态核查。关闭已消失窗口时不再访问其可见性，避免把成功关闭误判为清理失败。

实际输入入口现先经/usr/bin/osascript有界读取UI elements enabled，仅精确true才创建测试资源或切换源（ADR-135）；它不能替代逐键保护。新增回归命令：`python3 platforms/macos/tests/test-installed-textedit-probe.py`。用户界面允许某项授权不等同当前执行链已生效；本次授权后仍返回false/-1719，记BLOCKED而非输入失败或PASS。

2026-10-12更新（ADR-137/138）：已装TextEdit驱动先选独有源，再创建/首次激活文档，使用受控W=13/Q=12/Space=49物理键码；原来的先创建文档后选源在本机输出原码，换发键形式单独不能解决。当前正常路径已提交“你”，创建阶段failure/INT/TERM恢复通过；组合中断和多应用覆盖仍待验，旧live不开放。回归命令`python3 platforms/macos/tests/test-installed-textedit-probe.py`（6项）和`test-owned-resources.py`（7项）。不把这份c294b67隔离公证包当当前全部产品改动的最终候选。

ADR-139：`run-installed-textedit-probe.py <root> <helper> --scenario failure|INT|TERM`覆盖wq前缀之后、空格之前的恢复，成功状态只表示该场景验证通过，不表示正常提交或marked range已验。normal仍要求“你”提交。三条原生通过，原源/完整启用集合/真实数据保持；7项驱动回归加7项所有权回归通过。

ADR-140：已装TextEdit探针现核验AXTextInputMarkedRange，固定空文档wq阶段AppleScript端点1,2、提交“你”后2,1；范围不可读不允许提交。normal及确认范围后的failure/INT/TERM原生通过。这里是AppleScript端点格式，不能当CFRange location/length。驱动回归8项+所有权7项，其他客户端仍待验。

### Safari离线所有权夹具（ADR-141）

`safari-fixture.py <工作目录>`生成0700独占目录及0600本地HTML；无脚本/外部资源，CSP禁止加载。`owned-safari.applescript create|check|close <精确file URL> [window ID]`核验新窗口ID、单标签及URL；导航/新增标签拒绝关闭，不读取既有页面，不发键或选择源。创建失败无法取得ID时保留现场，不以front window回收。

设备B原生编译零诊断；首次create返回AppleEvent超时(-1712)，未取得ID，记BLOCKED，不宣称Safari覆盖通过。证据`build/safari-ownership-0uxjlkmp/result.json`。若窗口可能已创建，应先人工确认独有页面再清理；不要盲目重试创建。

ADR-142授权后更新：Safari自动化响应恢复，独有页面身份检查通过；关闭后的窗口对象可继续存在且visible=false、tabs=0。专用close接受此空隐藏状态，不接受有标签或可见对象。修复后四次顺序创建/检查/关闭通过，证据`build/safari-ownership-0uxjlkmp/fixed-result.json`；这些是重复所有权验证，未注入failure/INT/TERM，不代表输入或中断恢复通过。

### Safari正文实际输入（ADR-143）

`run-installed-safari-probe.py <已核验私有根> <source-state helper> [--scenario normal|failure|INT|TERM]`沿用TextEdit包签名/绑定、源日志和真实数据摘要保护；先选独有源再创建离线页面。Safari初始焦点实测是智能搜索栏，不能仅依赖HTML autofocus；初次激活后只枚举自有窗口中描述为夹具唯一名称的AXTextArea并聚焦。read/key同调用核验页面、前台窗口及AX角色/唯一名称；只允许13/12/49。焦点丢失停止，不重新抢回。

设备B正文正常wq+空格提交“你”（installed-safari-ryzelwii）；wq前缀核验后failure/INT/TERM通过（6fkc8ng0、ch4241os、3fc5ln2v）。原源/完整启用集合/真实数据摘要恢复，自有窗口关闭。未读取Safari marked range，因此只证明固定正文输入及前缀阶段恢复；不是完整预编辑协议、地址栏或最终产品候选验收。

### Terminal非执行接收器（ADR-144）

`terminal-input-sink.py <0700私有目录>`仅在TTY内读取至多64字节，最长30秒，stop标记或INT/TERM退出。无eval/exec/子进程，不执行输入；ready.json绑定PID/TTY，result.json仅记录empty/prefix/committed/unexpected分类，文件0600。退出恢复TTY属性，比较仅忽略macOS瞬态PENDIN位。`test-terminal-input-sink.py`四项伪终端测试通过（含INT和TERM两个信号）。

这是接收器验证，尚未接入Terminal原生窗口/TTY/进程身份及逐键焦点保护，禁止直接复用旧Terminal live发键入口。下一步先完成三者绑定，再验证实际IMK输入/恢复。

### Terminal窗口/TTY/进程绑定（ADR-145）

`run-terminal-ownership.py`创建私有接收器目录，用shell正确引用的固定exec命令创建独有窗口。`owned-terminal.applescript`记录新窗口ID和单标签TTY，检查/关闭均复核；Python核验ready的PID及ps精确命令/TTY。仅以stop标记终止接收器，结果确认恢复TTY后，窗口非busy才关闭。未取得ID保留现场，不退回前台窗口。

设备B原生编译通过，首次create失败；后续只读窗口数量查询明确AppleEvent超时(-1712)。证据`build/terminal-ownership-z0lqvymz/result.json`；四项PTY回归通过，但原生绑定及实际输入尚未通过。已请求用户核对Terminal自动化授权，不盲目重试。

ADR-146更新：用户授权后Terminal调用已恢复。Homebrew bin/python3.14启动器实际运行同版本Framework Resources/Python.app，驱动创建前固定预期运行路径；完整命令（含脚本/私有目录）及TTY仍精确匹配。原生绑定、empty接收、stop、TTY恢复和自有窗口关闭已通过，证据`build/terminal-ownership-ccynlyig/result.json`。`test-terminal-ownership.py`1项回归覆盖TTY、解释器、目录和额外参数漂移拒绝；接收器4项通过。尚未发送Terminal输入，不将此结果记为IMK客户端验收。

### Terminal实际输入及中断恢复（ADR-147）

`run-installed-terminal-probe.py <私有根> <source-state helper> [--scenario normal|failure|INT|TERM]`核验已装独有包签名/绑定及恢复日志，选源后创建非执行接收器窗口。每次W/Q/Space动作同调用检查窗口/TTY/前台/AXTextArea/PID完整命令；输入源也逐键检查，不发送回车或任意命令。正常接收器须committed；中断场景仅在AX正文去除尾部CR/LF/空格后wq后缀确认时注入。finally恢复原源/完整启用集合、stop接收器、确认TTY恢复并关闭非busy自有窗口，真实配置/词库摘要必须不变。

设备B正常通过`installed-terminal-tp05x0d3`；failure/INT/TERM通过`p93m28kf`、`5h66ex17`、`fyuau280`。初次前缀断言因尾部屏幕空白失败的证据`secvbit9`保留；该轮也安全恢复/关闭。没有marked range校验，固定场景通过不代表所有Terminal交互或最终候选。

Terminal结果门禁新增`test-installed-terminal-probe.py`两项回归：正常必须具备完整身份/焦点/恢复/清理及committed字节证据；中断必须具备前缀、注入信号及已知empty/prefix字节分类，unexpected不能PASS。加上身份与接收器回归共7项。

ADR-151：独立预览冒烟新增真实NSEvent+FFI组合导航回归，覆盖四方向/Shift、修饰透传、控制字符/函数键/空字符表示与退格/Esc/选字交互。此处不构成已装IMK客户端复验；IT-24须新签名包原生复验后关闭。

ADR-170/171：test-wubi-learning.py通过真实Rust只读ABI与Swift/生产CandidateWindow测试完整码、核验根码/识别码、长词摘要/逐字披露、137pt明细上限、独立Schema显示开关/快捷键及组合保持。只用私有数据和离屏图，不激活窗口/发键；不代替根码覆盖或最终实机验收。

ADR-182：`test-preview-menu.py`以真实Rust/Swift会话核验同组件菜单、私有配置、模式与四状态、外部设置/快捷键通知、写失败恢复与无学习副作用；不显示窗口，不替代系统IMK代理实机结果。

### 逐场景本地验收（ADR-192）

`make macos-local-acceptance`复用生产组件/真实FFI执行六组原生离屏场景，自动创建独立运行目录。不是安装包或正式系统IMK验收，不显示窗口、不发送桌面事件、不打开外链；只使用私有配置/词库及命名剪贴板。既有保护用例仅核对真实配置/词库摘要，不记录内容。

```sh
python3 platforms/macos/tests/run-local-acceptance.py --output platforms/macos/build/local-acceptance/my-new-run
python3 platforms/macos/tests/run-local-acceptance.py --check platforms/macos/build/local-acceptance/my-new-run
```

输出report.html/report.md/report.json、逐组observations.json和run.log、探针/依赖锁哈希、测试源码快照、截图及逐文件SHA。已存在目录拒绝覆盖，失败/中断的记录保留。直接动作派发/合成NSEvent/反馈打开模拟会在场景预期中标明，不改写为物理键盘、VoiceOver或实际浏览器测试。

本地PASS要求所有必需场景齐全、探针退出正常、观测和汇总一致、所需图像和源码快照存在且SHA一致、测试前后源树不变。`--check`检查保留下来的证据，不执行其中的程序；校验器的合成fixture只是拒绝假通过回归，不是产品通过证据。

正式schema 2门禁保持。报告中的MVP结果始终BLOCKED，23项正式必测单列；没有确定观察记录的历史手工操作不补填PASS。真正系统菜单/VoiceOver/客户端/安全字段/多屏/真实IMK性能/独立试用仍需后续记录。

## 真实IMK验收准备（不执行桌面动作）

```sh
python3 platforms/macos/tests/prepare-imk-acceptance.py --output platforms/macos/build/imk-preparation-NEW
```

只接受新目录；输出12组细化步骤、预期、证据与停止/恢复规则，以及全部BLOCKED的正式schema 2模板。候选/应用版本留空；不能用准备成功表示实机通过。入口无执行模式，不调用旧live脚本；真正执行前需当前空闲、同候选/宿主身份、私有数据及逐动作焦点保护。现有隔离驱动不能直接适配正式包，新菜单/VoiceOver交互保护仍待实现/实测。详见报告042与ADR-193。

## 正式包的账号数据隔离前置（ADR-194）

正式宿主固定使用真实登录用户的Application Support，不能用HOME覆盖或测试包冒充正式包。涉及写配置/词库时使用独立macOS测试账号；本工具只验证账号和已知数据路径边界，没有桌面执行能力。

```sh
# 原操作者账号：绑定精确候选归档及其commit，plan必须不存在
python3 platforms/macos/tests/formal-profile-guard.py bind --candidate /path/final.zip --commit FULL_SHA --plan /path/new-account-plan.json
# 独立账号：只读检查；同账号/root/伪HOME/链接/他人可写路径/归档漂移返回3
python3 platforms/macos/tests/formal-profile-guard.py check --candidate /path/final.zip --plan /path/new-account-plan.json
```

绑定单须人工核对来源并传入测试账号，它是上下文声明，不是授权凭据。PROFILE_READY仍为formal_result=BLOCKED；需要另验GUI登录会话、签名/公证、安装副本/运行宿主、当前空闲、权限及逐动作保护。路径检查仅代表当时快照，不消除检查后改路径的竞争；执行器仍需自己的保护，不得据此解禁旧live入口。现有隔离测试包继续只证明组件/隔离宿主；本工具不修改包身份或配置通道，也不创建系统账号。

## 候选/学习区逐动作原生AX保护（ADR-195）

`GuardedAXPress.swift` + `guarded-ax-main.swift`为测试专用工具，不编入产品；test-guarded-ax.py编译原生适配器并以注入后端执行保护回归。实际执行须独立测试账号、同账号GUI会话、可信最终候选/安装与宿主身份、当前空闲及拥有式TextEdit文档。旧live入口未开放。

编译时将guarded-ax-main.swift复制到临时目录main.swift，使用`swiftc -warnings-as-errors GuardedAXPress.swift 临时目录/main.swift -o 临时目录/guarded-ax`。CLI只接受`--inspect plan.json`（指定路径只读观察）和`--press plan.json`（一个AXPress）；不自动发现、激活或重试。

计划结构对应GuardedPressPlan：operatorUID/testUID/home/sourceID；runDirectory必须为700私有的lampyris-formal-UUID目录，fixture为其直接子文件（600、无符号/硬链接），fixtureTitle匹配文件名；client/host包含pid、executable规范绝对路径、sha256、launchedAt（实际launchDate.timeIntervalSince1970）。target包含windowIndex、childPath索引数组、windowTitle、windowFrame（NSStringFromRect格式）、label（AXDescription优先，非空时精确匹配）。绑定必须来自当次已验证自有测试对象，不能猜测PID/子路径或使用旧运行值。

当前仅支持com.apple.TextEdit和正式cn.jokerhub.inputmethod.Lampyris宿主内AXButton；输入源固定正式.default。核对账号/GUI/权限、私有文件、客户端/宿主实际执行文件摘要和启动时间、前台/焦点文档/文本域、输入源，再解析明确窗口/控件路径；解析后再次核对上下文与目标。失败无后续Press、无抢焦点、无模糊匹配/坐标点击。跨进程检查与动作非系统原子事务，必须保持空闲；源与文档恢复由外层驱动负责，不能将单动作返回成功等同于业务或正式MVP通过。系统菜单代理、滚动、按键和VoiceOver不在此入口范围。
