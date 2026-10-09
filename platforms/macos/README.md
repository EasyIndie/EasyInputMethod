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
│   ├── YinghuoTemplate.png / @2x.png # 菜单模板图标
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

产出 `platforms/macos/build/Yinghuo.app`（已做 ad-hoc 签名）。

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
| `data/generated/pinyin-core.tsv` | ✅ 已入库（256KiB） | 拼音降级为单音节 |

复现大文件：

```sh
./data/sources/fetch-jieba-dict.sh        # 以及 fetch-pinyin-data.sh / fetch-phrase-pinyin.sh
cargo run -p ime-pinyin --example generate
python3 tools/prepare-pinyin-core.py
```

## 手动装载（历史基础输入验收通过，当前候选待验收）

ADR-023 修正后的经典 `.app` + IMKServer 已通过本机 macOS 27 装载验收：Developer ID 签名、公证、系统域安装、重启后，用户确认 TextEdit/Safari 的 `wq→你`、`nihao→你好` 正常。每次重新构建仍须重新签名/公证；`build.sh` 的 ad-hoc 产物用于开发校验。流程已固化在 packaging/macos/ 与 install.sh/uninstall.sh；最终候选安装验收待完成。

1. 构建：`./platforms/macos/build.sh`。
2. 在 GUI Terminal 里，对构建产物使用自己的 Developer ID 身份重新签名、公证：
   ```sh
   codesign --force --options runtime --timestamp \
     --sign "Developer ID Application: <姓名 (TEAMID)>" platforms/macos/build/Yinghuo.app
   ditto -c -k --keepParent platforms/macos/build/Yinghuo.app /tmp/Yinghuo-notary.zip
   xcrun notarytool submit /tmp/Yinghuo-notary.zip --keychain-profile "<凭据名>" --wait
   xcrun stapler staple platforms/macos/build/Yinghuo.app
   spctl -a -vvv -t exec platforms/macos/build/Yinghuo.app
   ```
   公证须为 Accepted，`spctl` 须为 `accepted / Notarized Developer ID`。这些是信任检查，不代表输入法发现已通过。
3. 用修正后的包替换原安装包，仅保留一个安装位置；清除同 bundle 的 LaunchServices 影子登记。不要修改已签名包的 plist，否则签名和公证失效。
4. 保存工作后，注销并重新登录（或重启），再运行下面的诊断工具。
5. 若枚举到新 ID，在系统设置 → 键盘 → 文字输入 → 输入法中添加「萤火虫」，验证 TextEdit/Safari 的 `wq→你`、`nihao→你好`。

### 装好却看不到？先跑诊断

```sh
./platforms/macos/tools/list-input-sources.sh yinghuo
```

- 有输出（含 `yinghuo` / `org.yinghuo`）→ 系统已识别，去「系统设置 → 键盘 → 输入法」添加；
- 无输出 → 装载未通过。核查新 ID、签名/公证、安装路径和影子登记，并检查 `imklaunchagent` 日志；不能仅凭无输出断言未重登或必须改为 appex。

## 日常开发：独立调试窗口

在仓库根目录运行：

```sh
make macos-preview
# 仅构建，或运行自动冒烟检查：
./platforms/macos/dev-preview.sh --build-only
./platforms/macos/dev-preview.sh --smoke-test
```

需要 Rust、Xcode/Swift 和本页所述三份 `data/generated/` 真实词典。脚本增量构建 debug `ime-ffi`，链接普通 AppKit 应用到 `platforms/macos/build/preview/YinghuoPreview.app`，直接运行；无需 Developer ID 签名、公证上传、系统目录安装、输入源注册或重启。Apple Silicon 链接器生成的本地签名不涉及开发者证书。词典通过资源符号链接读取，不复制大表。修改代码后关闭窗口，重新运行命令即可；本机缓存后构建一次约 4.25 秒（非性能保证）。

窗口直接接收原始按键，复用正式宿主的 `ImeSession`、`ime-ffi` 与 `CandidateWindow`。支持末尾输入、组合串、五笔/拼音/混输、空格/数字/回车选字、退格删码、Esc 取消和清空。它是输入测试区，暂不支持任意光标位置编辑或完整文本编辑快捷键。启动通过 `ime-config` 读取同一配置路径；模式下拉框只改变当前会话，不保存配置。

自动冒烟检查覆盖真实词典、文本渲染和上述按键流程；窗口可用于大多数引擎及候选窗迭代。IMK 事件分发、跨应用光标定位、输入源注册和系统生命周期仍需在已安装的输入法中验收。调试应用使用独立标识，不替换系统中的 `Yinghuo.app`。设计见 ADR-024。

## 验证打字

1. 打开 TextEdit，切换到「萤火虫」输入法。
2. 打 `wq` → 候选窗出现 → 空格/数字上屏 → 得到「你」。
3. `kwwl` → 「中华人民共和国」；`nihao`（混输自动拼音兜底）→ 「你好」。
4. 退格删码、Esc 取消组合。

## 配置

- **唯一配置文件**：`~/Library/Application Support/萤火虫/config.toml`
  （宿主启动时经 `ime_config_init` 告知引擎，绝不使用 `UserDefaults`，见 `docs/配置架构.md`）；
- 首次运行前文件可以不存在 → 使用 Schema 默认值；外部修改约 350–550ms 后加载；语法错误保留上一份有效配置。正式宿主下一次按键应用模式/页大小，候选窗主题自动刷新。
- 切换模式：文本输入菜单里的「切换输入模式」（当前实现；正式交互属 P1-M4），
  或直接改 `config.toml` 的 `mode = "mixed" | "wubi" | "pinyin"`。

## 已知限制 / 待人工验证

- 正式候选已在 macOS 27 / Apple Silicon 通过实体输入、分页、退格/Esc、失焦清理、回车原码、模式切换、拼音反查及图标显示复核，详见 `docs/reviews/005-macos-formal-acceptance.md`。
- 候选窗支持分页、亮暗主题和屏幕边界限制；真实客户端长时间使用、光标定位与撤销行为仍需按发布清单逐项验收。
- 候选为 **universal（arm64 + x86_64）**，由 CI 构建；macOS 13（Intel）已用 ad-hoc 在本机完成实体输入验收（ADR-055）。目标 macOS 13+ 不代表所有版本均经实机验收。
- 用户词库菜单和重启保留、完整 IMK 端到端性能及长时间多应用验收仍待完成，见 `docs/macos-release-checklist.md`。

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

Ctrl+Shift+Space 临时中英切换，Shift+Space 临时全半角；切换取消当前组合。三模式循环快捷键来自 hotkey.toggle_mode（默认 Ctrl+Shift+M），正式宿主经 ime-config 保存模式，预览只改变会话。中文标点通过 input.punctuation 控制，双/单引号依次输出成对引号；全角偏好通过 input.full_width 控制。组合中标点先上屏当前页首候选；没有候选时保留原码。

## 用户词库与学习

默认在 `~/Library/Application Support/萤火虫/user-dictionary.tsv` 保存词条数据（不是配置）。显式选字按完整编码累加使用次数，精确用户词条优先于前缀预测，同来源候选按本地使用次数排序；没有时间戳、输入历史或联网同步。预览提供新增/导入/导出按钮，正式宿主输入菜单提供对应入口。

格式为 `scheme\tcode\ttext\tcount`，scheme 为 wubi/pinyin，code 为不带空格的小写编码，count 为正整数。最多 10000 条/2MiB；无效导入不覆盖原文件，重复导入合并取最大次数。导出不得覆盖配置或正在使用的词库。跨会话更新在下一次输入前读取；学习读写失败保留已选文字，预览状态/正式输入菜单显示错误。崩溃留下 user-dictionary.lock 时，请先关闭所有萤火虫会话、备份词库，再移除该锁文件后重试。分发包不包含用户词库。

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

脚本生成临时满容量合成词库，不读取真实用户词库，不安装输入法。第一项测引擎及选字学习落盘；第二项运行五会话、22000按键，逐段记录窗口内存，并对探针自身采样 IP 连接。GUI 探针按输入序列释放临时对象并排空主循环；计时包含 FFI/候选转换/布局/显示调用，不含正式 IMK 客户端或合成器完成。结论与局限见 `docs/reviews/003-macos-performance.md`。

组合中按 Return/Enter 提交原始字母，空格或数字键提交中文候选；非组合态回车交由当前应用处理。

正式宿主在组合结束、输入源停用及当前客户端应用失活时取消未选组合，清空预编辑并隐藏候选；不自动提交未选择文字。

多页候选显示“当前页/总页数”，用 `-`/`=` 或 Page Up/Page Down 翻页；每页默认七项，数字键选当前页候选。

### 解压权限与菜单栏外观

发行ZIP使用Finder或 `ditto -x -k <候选.zip> <目录>` 解压，保留程序执行权限。Python zipfile.extractall等丢失权限的解压方式会使输入源可见但宿主无法启动；安装预检拒绝这种候选。菜单栏采用18pt透明单色飞行萤火虫符号与2x资源，Info.plist声明 `TISIconIsTemplate=true`，跟随系统菜单栏亮暗及选中着色；无需新增配置文件。
