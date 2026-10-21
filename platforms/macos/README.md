# 萤火虫输入法 · macOS 宿主（Swift + InputMethodKit）

平台薄壳：捕获按键 → 调用 `ime-ffi` C ABI → 渲染候选窗并上屏。
**引擎与业务逻辑 100% 在 Rust（`crates/`）**，本目录不含输入逻辑。

所有 UI 使用纯代码 AppKit；构建无需 Interface Builder。正式候选使用 Developer ID 签名与 Apple 公证，日常开发使用独立调试窗口。

## 目录

```
platforms/macos/
├── build.sh                       # cargo staticlib + swiftc → .app bundle
├── Info.plist                     # IMK 键名（参照系统/第三方输入法实测）
├── Resources/
│   ├── LampyrisTemplate.png / @2x.png # 菜单模板图标
│   └── zh-Hans.lproj/·en.lproj/InfoPlist.strings  # 本地化显示名
├── Sources/
│   ├── main.swift                 # NSApplication + IMKServer 入口
│   ├── InputController.swift      # IMKInputController 子类（按键 → FFI）
│   ├── ImeSession.swift           # FFI 会话封装（指针转换）
│   ├── CandidateWindow.swift      # 纯代码候选窗（NSPanel）
│   └── Config.swift               # 配置读取 + 平台路径
├── tools/list-input-sources.sh    # 诊断：系统是否识别到本输入法
└── tests/
    ├── ffi_smoke.swift            # 真实数据运行时冒烟（不涉及 IMK）
    └── run-ffi-smoke.sh
```

## 前置

- 目标 macOS 13+；本轮 macOS 27 / Apple Silicon，早期 Intel 13.7 编译记录不等于完整发布验收；
- Xcode **或** Command Line Tools（含 `swiftc`、`clang`、`codesign`）；
- Rust 工具链（见仓库根 `rust-toolchain.toml`），Python 3（发布路径归一化/附件生成）。

## 构建

```sh
./platforms/macos/build.sh
```

产出 `platforms/macos/build/Lampyris.app`（已做 ad-hoc 签名）。

> **必须是 `.app`，不能是 `.inputmethod`。** 本机实测：macOS 13 的 LaunchServices
> 无法扫描 `.inputmethod`（报 `-10811`），且系统里所有输入法都是 `.app`（见 ADR-022）。

可选：验证「真实数据 + Swift 链接 + 引擎输出」（需要 `data/generated/` 数据文件）：

```sh
./platforms/macos/tests/run-ffi-smoke.sh
# 期望输出：✅ FFI 运行时冒烟通过：wq→你，nihao→你好
```

### 数据文件

下表是普通开发构建的降级行为；发布与 CI 使用 `--strict`，缺失任一默认数据立即失败。

`build.sh` 会把这些文件打进 bundle 的 `Contents/Resources/`：

| 文件 | 是否入库 | 缺失时 |
|---|---|---|
| `data/generated/wubi86-core.tsv` | ✅ 已入库 | 宿主回退内置样本引擎 |
| `data/generated/pinyin-chars.tsv` | ✅ 已入库 | 不启用拼音 |
| `data/generated/pinyin-core.tsv` | ✅ 已入库（20k基础词及场景训练词，ADR-227） | 拼音降级为单音节 |

复现大文件：

```sh
./data/sources/fetch-jieba-dict.sh        # 以及 fetch-pinyin-data.sh / fetch-phrase-pinyin.sh
cargo run -p ime-pinyin --example generate_pinyin
python3 tools/prepare-pinyin-core.py
```

## IMK包标识与注册排错（ADR-120…122）

本仓库的生产和隔离输入法bundle标识必须保留完整的`.inputmethod.`命名段。生产为`cn.jokerhub.inputmethod.Lampyris`，隔离为`cn.jokerhub.inputmethod.LampyrisIMKTest.<UUID>`。这指bundle标识，不是包后缀；包后缀仍为`.app`。模式ID和连接名必须由同一身份派生，不能只改CFBundleIdentifier。

设备B（macOS27/arm64）的实机对照：原隔离标识`cn.jokerhub.lampyris.imktest.<UUID>`在软链、实体ad-hoc及实体Developer ID三种条件下均出现TIS返回0而无对应输入源。保留`.inputmethod.`后，实体ad-hoc包枚举了父源与default模式两个身份。初次证据目录为`build/source-probe-identity-7cb49b02/`；完整驱动复跑证据为`build/source-probe-e2e-6aadf5a7/`（注册/完整恢复exit0），旧失败目录见IT-01任务卡。这是该设备的因果对照和仓库命名契约，尚未证明所有macOS版本均如此；Apple SDK只描述模式ID构造中的该命名段，不据此伪称官方强制规则。

排查“注册返回0但没有输入源”时：先核对完整bundle标识、两份模式清单及连接名，再看LaunchServices识别结果，最后在TIS中核对精确ID与bundle属性。不要仅凭返回0、lsregister成功或有签名就宣称注册成功，也不要无依据反复请求辅助功能权限。身份检查已接入隔离构建与实体注册前置校验，CI回归拒绝缺段标识、连接名或模式清单漂移。

清理时TISDisable返回0也不足以证明状态恢复：设备B实测default模式可暂仍显示enabled。仅在当前源和非测试启用集合未变、整个测试文件树仍匹配时，注销并移除自己的实体包，再用新进程检查完整启用集合恢复及测试身份均禁用。系统可能保留禁用缓存；不要删除系统偏好或其他输入法来清理缓存。详细安全入口见[测试规范](tests/README.md)。

## 手动装载（历史基础输入验收通过，当前候选待验收）

ADR-023 修正后的经典 `.app` + IMKServer 已通过本机 macOS 27 装载验收：Developer ID 签名、公证、系统域安装、重启后，用户确认 TextEdit/Safari 的 `wq→你`、`nihao→你好` 正常。每次重新构建仍须重新签名/公证；`build.sh` 的 ad-hoc 产物用于开发校验。流程已固化在 packaging/macos/ 与 install.sh/uninstall.sh；最终候选安装验收待完成。

1. 构建：`./platforms/macos/build.sh`。
2. 在 GUI Terminal 里，对构建产物使用自己的 Developer ID 身份重新签名、公证：
   ```sh
   codesign --force --options runtime --timestamp \
     --sign "Developer ID Application: <姓名 (TEAMID)>" platforms/macos/build/Lampyris.app
   ditto -c -k --keepParent platforms/macos/build/Lampyris.app /tmp/Lampyris-notary.zip
   xcrun notarytool submit /tmp/Lampyris-notary.zip --keychain-profile "<凭据名>" --wait
   xcrun stapler staple platforms/macos/build/Lampyris.app
   spctl -a -vvv -t exec platforms/macos/build/Lampyris.app
   ```
   公证须为 Accepted，`spctl` 须为 `accepted / Notarized Developer ID`。这些是信任检查，不代表输入法发现已通过。
3. 用修正后的包替换原安装包，仅保留一个安装位置；清除同 bundle 的 LaunchServices 影子登记。不要修改已签名包的 plist，否则签名和公证失效。
4. 保存工作后，注销并重新登录（或重启），再运行下面的诊断工具。
5. 若枚举到新 ID，在系统设置 → 键盘 → 文字输入 → 输入法中添加「萤火虫」，验证 TextEdit/Safari 的 `wq→你`、`nihao→你好`。

### 装好却看不到？先跑诊断

```sh
./platforms/macos/tools/list-input-sources.sh lampyris
```

- 有输出（含 `lampyris` / `cn.jokerhub`）→ 系统已识别，去「系统设置 → 键盘 → 输入法」添加；
- 无输出 → 装载未通过。核查新 ID、签名/公证、安装路径和影子登记，并检查 `imklaunchagent` 日志；不能仅凭无输出断言未重登或必须改为 appex。

## 快速本地验收（推荐）

```sh
make macos-dev
```

该入口重建预览后启动唯一身份的隔离应用，窗口内“输入法菜单”复用正式InputStateMenu，“偏好设置”使用正式面板；输入、模式下拉框、菜单、快捷键与设置即时同步。每轮使用自己的临时配置和词库，不替换已装输入法、不注册/切换系统输入源。关闭窗口或在启动终端输入`close`结束，修改代码后重跑命令查看；不提供热重载，正常结束不保留本轮临时设置。失败保留的独有目录见终端RETAINED提示。

可点验四状态文案、模式行点击循环、快捷键/设置同步、学习区和词库工具。它不能证明系统状态栏代理的实际跟踪/闭合、IMK跨应用输入或真实VoiceOver已通过。完整分层流程见[开发工作流](../../docs/开发工作流.md)。

## 历史入口：独立调试窗口（真实配置）

在仓库根目录运行：

```sh
make macos-preview
# 仅构建，或运行自动冒烟检查：
./platforms/macos/dev-preview.sh --build-only
./platforms/macos/dev-preview.sh --smoke-test
```

需要 Rust、Xcode/Swift 和本页所述三份 `data/generated/` 真实词典。脚本增量构建 debug `ime-ffi`，链接普通 AppKit 应用到 `platforms/macos/build/preview/LampyrisPreview.app`，直接运行；无需 Developer ID 签名、公证上传、系统目录安装、输入源注册或重启。Apple Silicon 链接器生成的本地签名不涉及开发者证书。词典通过资源符号链接读取，不复制大表。修改代码后关闭窗口，重新运行命令即可；本机缓存后构建一次约 4.25 秒（非性能保证）。

窗口直接接收原始按键，复用正式宿主的 `ImeSession`、`ime-ffi` 与 `CandidateWindow`。支持末尾输入、组合串、五笔/拼音/混输、空格/数字/回车选字、退格删码、Esc 取消和清空。它是输入测试区，暂不支持任意光标位置编辑或完整文本编辑快捷键。启动通过 `ime-config` 读取同一配置路径；模式下拉框只改变当前会话，不保存配置。

自动冒烟检查覆盖真实词典、文本渲染和上述按键流程；窗口可用于大多数引擎及候选窗迭代。IMK 事件分发、跨应用光标定位、输入源注册和系统生命周期仍需在已安装的输入法中验收。调试应用使用独立标识，不替换系统中的 `Lampyris.app`。设计见 ADR-024。

## 验证打字

1. 打开 TextEdit，切换到「萤火虫」输入法。
2. 打 `wq` → 候选窗出现 → 空格/数字上屏 → 得到「你」。
3. `kwwl` → 「中华人民共和国」；`nihao`（混输自动拼音兜底）→ 「你好」。
4. 退格删码、Esc 取消组合。

## 配置

- **唯一配置文件**：`~/Library/Application Support/Lampyris/config.toml`
  （宿主启动时经 `ime_config_init` 告知引擎，绝不使用 `UserDefaults`，见 `docs/配置架构.md`）；
- 首次运行前文件可以不存在 → 使用 Schema 默认值；外部修改约 350–550ms 后加载；语法错误保留上一份有效配置。正式宿主订阅配置变化并刷新模式/页大小/外观；审计009发现部分候选相关选项在组合中未重算，修复见 IT-06。
- 切换模式：文本输入菜单显示当前「混输 / 五笔 / 拼音」并点击循环切换（ADR-079），
  或直接改 `config.toml` 的 `mode = "mixed" | "wubi" | "pinyin"`。

## 已知限制 / 待人工验证

- 正式候选已在 macOS 27 / Apple Silicon 通过实体输入、分页、退格/Esc、失焦清理、回车原码、模式切换、拼音反查及图标显示复核，详见 `docs/reviews/005-macos-formal-acceptance.md`。
- 候选窗支持分页、亮暗主题和屏幕边界限制；真实客户端长时间使用、光标定位与撤销行为仍需按发布清单逐项验收。
- 候选为 **universal（arm64 + x86_64）**，由 CI 构建；macOS 13（Intel）已用 ad-hoc 在本机完成实体输入验收（ADR-055）。目标 macOS 13+ 不代表所有版本均经实机验收。
- 用户词库操作及重启保留已有历史验收；完整 IMK 性能、长时间多应用、多屏/缩放和最终签名包仍需补验，见 `docs/迭代计划.md`。真实环境脚本需先完成 IT-01/02 数据保护修复。

## 为宿主扩展的 `ime-ffi` 入口（T-M3-02）

| 函数 | 作用 |
|---|---|
| `ime_session_new_with_data(wubi, chars, words)` | 从真实 TSV 创建会话（词表可空） |
| `ime_session_buffer(session)` | 借用组合缓冲区（预编辑串） |
| `ime_session_set_mode(session, mode)` | 切换模式 |
| `ime_session_key(...)` | 成功时返回 `IME_KEY_CONSUMED/_COMMITTED/_PASS_THROUGH` |
| `ime_config_init(path)` | 宿主设定唯一配置路径（须最先调用） |

全部入口仍 `catch_unwind` 兜底、坏输入返回错误码；真实 `unsafe` 只存在于 `ime-ffi`。

## 应用图标

正式宿主和独立调试应用使用飞行萤火虫官方图标，构建时从 `assets/icons/yinghuo-official-app.icns` 复制。项目保留全部设计版本及原图，见 `assets/icons/README.md`。

## CI 覆盖

macOS job 独立运行 Rust 全量验证、正式宿主构建、按登记许可及校验和复现拼音数据、独立窗口冒烟和图标校验。仅本地 ad-hoc 构建校验，不使用 Developer ID、不上传公证、不安装系统输入法。跨应用物理键盘、光标、撤销及长时间稳定性仍需实机验收；远端通过状态以 PR 检查为准。

## 候选翻页

组合中使用 `-` / `=`（或 `+`）、PageUp/PageDown 翻页；空格、回车和数字只选择当前页。首末页不循环，继续输入或删码回第一页。每页数使用 `candidate.count`（3–9）；每引擎最多保留 256 条结果，超出不继续翻页。候选分页由 Rust 核心统一管理，两个宿主共用。

配置实时生效使用 ime-config 的 FileWatcher 和唯一快照；预览冒烟使用隔离的临时配置，不写用户偏好。独立窗口模式下拉框仍是临时会话状态。

已有引擎配置现已接入：`wubi.auto_commit` 控制四码唯一自动上屏，`wubi.z_key` 控制 z 单字通配，`pinyin.fuzzy` 提供首音节 zh/z、ch/c、sh/s、n/l 模糊匹配。组合模糊音与整句预测留在 P2。

## 输入交互

单独按 Shift（松开且期间无其它键，默认）临时中英切换，Ctrl+Shift+Space 临时全半角；切换取消当前组合。三模式循环快捷键来自 hotkey.toggle_mode（默认 Ctrl+Shift+M），正式宿主经 ime-config 保存模式，预览只改变会话。中文标点通过 input.punctuation 控制，双/单引号依次输出成对引号；全角偏好通过 input.full_width 控制。组合中标点先上屏当前页首候选；没有候选时保留原码。

## 用户词库与学习

默认在 `~/Library/Application Support/Lampyris/user-dictionary.tsv` 保存词条数据（不是配置）。显式选字按完整编码累加使用次数，精确用户词条优先于前缀预测，同来源候选按本地使用次数排序；没有时间戳、输入历史或联网同步。预览提供新增/导入/导出按钮，正式宿主输入菜单提供对应入口。

格式为 `scheme\tcode\ttext\tcount`，scheme 为 wubi/pinyin，code 为不带空格的小写编码，count 为正整数。最多 10000 条/2MiB；无效导入不覆盖原文件，重复导入合并取最大次数。导出不得覆盖配置或正在使用的词库。跨会话更新在下一次输入前读取；学习读写失败保留已选文字，预览状态/正式输入菜单显示错误。崩溃留下 user-dictionary.lock 时，请先关闭所有萤火虫会话、备份词库，再移除该锁文件后重试。分发包不包含用户词库。完整排查与手工恢复步骤（残留锁/容量/权限/数据缺失）见 [`docs/故障恢复.md`](../../docs/故障恢复.md)。

默认正式/预览已改用 pinyin-core.tsv（ADR-031），不加载 340k 全量词表。全量表只用于派生核心词表；生成校验和与规则见 data/generated/pinyin-core-report.json。

## 发布候选

完整打包流程与边界见 ../../packaging/README.md。`build.sh --strict` 在数据缺失时直接失败；发布必须使用严格构建。`install.sh --dry-run` 也要求已签名、公证并通过 Gatekeeper，ad-hoc 构建不能安装。卸载保留词库与设置，先在系统设置移除输入源、关闭宿主；`--system` 仅在明确管理员操作时使用。

### 拼音反查

独立窗口的「拼音反查」按钮与正式输入菜单的同名入口均使用内置字/词表；输入「你好」得到 `ni hao`。显示首选无调读音，未知字/词提示未收录；查询不上网、不保存记录。界面打开前取消组合，底层查询本身不改变候选与学习状态（ADR-034）。

菜单切模式或打开词库/反查面板前会取消预编辑并隐藏候选，避免残留。模式保存失败不切换。失焦/清空会重新开始引号配对，普通选字仍保持一句内的引号配对（ADR-036）。

长候选超过屏幕宽度时自动竖排；单条超长词显示截断文字、悬停显示完整 tooltip，选字仍插入完整词条。候选面板自身限制在当前屏幕可见区域（ADR-037）。独立冒烟含窄屏/屏幕边缘/超长词条的几何验证。

### 隔离性能预检

```sh
bash platforms/macos/tests/run-perf.sh 5 --max-user-dictionary
bash platforms/macos/tests/run-render-perf.sh --max-user-dictionary --stress
```

脚本生成临时满容量合成词库，不读取真实用户词库，不安装输入法。第一项测引擎及选字学习落盘；第二项运行五会话、22000按键，逐段记录窗口内存，并对探针自身采样 IP 连接。GUI 探针按输入序列释放临时对象并排空主循环；计时包含 FFI/候选转换/布局/显示调用，不含正式 IMK 客户端或合成器完成。**基线口径（T-MVP-09）**：以 `run-perf.sh`（引擎层、C 探针）为**稳定回归基线**；`run-render-perf.sh`（含 AppKit 同步调用）在本机（Intel/OLP）波动大（p95 9–27ms），仅作**参考**，不作为回归判据。结论与局限见 `docs/reviews/003-macos-performance.md`。

组合中按 Return/Enter 提交原始字母，空格或数字键提交中文候选；非组合态回车交由当前应用处理。

正式宿主在组合结束、输入源停用及客户端失活时尝试取消未选组合、清空预编辑并隐藏候选；Safari/Chrome 地址栏部分失焦场景仍会保留原码，已接受并在发布说明披露（UX-1）。

多页候选显示“当前页/总页数”，用 `-`/`=` 或 Page Up/Page Down 翻页；每页默认七项，数字键选当前页候选。

### 解压权限与菜单栏外观

发行ZIP使用Finder或 `ditto -x -k <候选.zip> <目录>` 解压，保留程序执行权限。Python zipfile.extractall等丢失权限的解压方式会使输入源可见但宿主无法启动；安装预检拒绝这种候选。菜单栏采用18pt透明单色飞行萤火虫符号与2x资源，Info.plist声明 `TISIconIsTemplate=true`，跟随系统菜单栏亮暗及选中着色；无需新增配置文件。

### 构建身份（ADR-113）

构建前检查所需Rust目标，缺项不会开始编译或清理旧暂存目录。源码Info.plist只保留产品字段；应用plist中的SDK/构建系统/Xcode身份由实际所选SDK和工具链派生，CLT不虚构Xcode字段。`python3 tools/macos-build-metadata.py check-contract platforms/macos/Info.plist platforms/macos/build/Lampyris.app/Contents/Info.plist`只核对产品契约；签名、公证与最终源码身份仍按分发流程验收。

### 隔离实体包路径与显示名称（ADR-124/126）

测试包的`IMKTestRoot`为0600所有权声明，不是配置文件；Python可能返回`/private/var/...`，Foundation的规范化路径可能为`/var/...`，应按同一规范化规则比较，不能以原始字符串判定不同目录。错误声明和过宽权限均须拒绝启动。

设备B实测`CFBundleDisplayName`设为中文隔离名称时，TIS父源实际名称仍为`LampyrisIMKTest`，模式名称为完整测试ID。向用户提供添加名称前先读取`kTISPropertyLocalizedName`；TIS枚举、启用返回0、父源真正启用、系统设置可添加及模式选择成功是不同检查。当前父源仍disabled、选择返回-50，原因未证实，不能直接归因权限。用户改变输入源后不得按旧日志强行恢复。

### 登录扫描与隔离根生命周期（ADR-130…132）

设备B本次对照：TIS登记/服务端点提交、Developer ID签名及公证accepted均不能证明立即可选择；重新登录后父源与模式启用，选择/恢复四路径通过。旧未公证测试源也同时出现，因此不能把公证称为本次发现生效的唯一原因；这只是当前系统/登录会话的观察，不是所有macOS必须注销的保证。

私有临时根可能在重新登录时被系统清理，菜单可见不代表测试入口能启动。已绑定公证包不得下载后改IMKTestRoot；需要先验证签名/票据/UUID/声明/系统临时路径，再独占恢复同一0700空根和0600所有权标记，配置仍由ime-config初始化。不得恢复到真实Lampyris目录。已装已启用源测试需以新基线保持其完整启用集合，不直接复用会注销移除包的注册驱动。

### 隔离验收：重复启用和实际授权主体

设备B本次已启用父源/模式的选择探针中，重复调用TISEnableInputSource(parent)后系统设置立即成为前台。助手先读取enabled，仅未启用时调用启用API，避免无意义副作用；修复后四路径恢复通过。此为本机观察，不能推广为所有版本保证，也不能取消逐键焦点保护（ADR-134）。

Codex辅助功能/自动化显示允许，不保证子进程执行路径都已获授权。本次对自有TextEdit控件的只读AX查询明确返回“osascript不允许辅助访问”（-1719）；以tccd日志的responsible/subject及精确宿主路径为准请求用户允许，报错中的执行者名称不能单独确定授权主体，不通过绕过AX检查继续发键。输入源发现/选择、前台检查、AX授权、真实提交分别记录。

2026-10-12责任归属对照（ADR-136）：本机实际链ChatGPT.app→内嵌CodexCLI→Python→osascript。TCC责任主体com.openai.codex、路径/Applications/ChatGPT.app，显示名称ChatGPT；允许该精确宿主后UI elements enabled=true且AX检查通过。不要按应用显示名或osascript报错猜测需授权哪个实体，先用进程PID对应日志。证据build/tcc-chain-2n0505ky；未重置TCC或读取其数据库。原生提交断言仍单独待诊断，不等同最终MVP通过。

组合中四方向键（含Shift）保持预编辑与候选，不移动客户端光标或选择候选；非组合态及Command/Control/Option导航透传。使用数字/空格选字、既有翻页键翻页（ADR-151）。

2026-10-16（ADR-181）：四个状态菜单以当前中文/英文、全角/半角、简体/繁体及中文/英文标点文案呈现，无布尔勾选；输入模式一级项显示当前模式并循环切换，二级项直接选择并同步唯一勾选。快捷键按钮不带省略号，学习区默认Ctrl+Shift+L、全/半角默认Ctrl+Shift+Space。已有显式配置（含none或旧Shift+Space）保持原值，需在设置中修改；不静默覆盖。

2026-10-16（ADR-183）：macOS14及以上的模式当前值使用原生尾部状态标签，随菜单宽度放在子菜单箭头左侧；macOS13用按实际菜单宽度计算的文本回退。模式值同时提供AXValue。候选翻页箭头与页码共享页眉中心，页码宽度包含原生cell内边距，保持完整多位页码。

2026-10-16界面反馈（ADR-191/报告039）：菜单设置/关于及动作按钮取消省略号，模式行使用系统SF Symbol箭头；设置带说明项统一文字间距。使用独立工作树make macos-dev关闭后重跑查看，主目录旧Makefile/源码不覆盖。正式IMK/键盘VoiceOver门禁仍待。

本地留痕验收（ADR-192）：使用make macos-local-acceptance（独立工作树内），自动执行生产组件/FFI离屏场景并保存逐项预期/实测值、源树与探针哈希、截图和报告。--check可复核原始证据；不等同真实系统IMK/物理键盘/VoiceOver，未记录手工项继续待验。

2026-10-17（ADR-198/199）：关于窗口标题为“关于”，复制诊断成功提示为“诊断信息已复制”；按钮按收起标题的原生尺寸居中排布。已有输入会话重新激活时统一同步持久mode，避免停用期间其它客户端/设置更改后保留旧模式。系统菜单代理丢弃自定义行后的右对齐与点击行为仍待实机修复验证，不能用独立预览证明。

2026-10-17（ADR-205，已被 ADR-206 取代）：曾采用标准“输入模式：当前模式”一级和三个二级选项，一级仅展开。

2026-10-18（ADR-206，当前菜单方案）：取消子菜单，恢复单行“输入模式：当前模式”并点击循环；模式值右对齐到与其它项相同的内边距，不再绘制箭头；直接三选一保留在设置页与 `hotkey.toggle_mode`。依据报告067：IMK 输入菜单不投递子菜单子项命令，父项挂子菜单后点击也不再循环。本地组件、私有 IMK 与真机验证分别记录，不能用本地探针宣称系统链路已通过。

### 固定身份的真实 IMK 开发源（ADR-230）

引擎/UI优先 `make macos-dev`。需要真实IMK时，`make macos-imk-dev ACTION=init`只初始化一次本机私有长期根；公证工作流使用相同target_root及development=true，之后 `make macos-imk-dev ACTION=install APP="<签名包>" ARGS=--stop-host`复用同一身份并保留开发数据与旧包。不自动移除/添加/切换输入源；首次添加仍可能需要注销。免注销更新必须在目标设备验证新PID/执行SHA及真实输入后才能确认。完整步骤、官方依据、回退和未决见[报告106](../../docs/reviews/106-stable-imk-development.md)。该路径不替代正式RC安装验收。
