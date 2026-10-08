# 萤火虫输入法 · macOS 宿主（Swift + InputMethodKit）

平台薄壳：捕获按键 → 调用 `ime-ffi` C ABI → 渲染候选窗并上屏。
**引擎与业务逻辑 100% 在 Rust（`crates/`）**，本目录不含输入逻辑。

> ⚠️ 本机**仅装 Command Line Tools、无 Xcode**，因此**不使用 Interface Builder /
> Asset Catalog**（`actool`/`ibtool` 是 stub）；所有 UI 为纯代码 AppKit。

## 目录

```
platforms/macos/
├── build.sh                       # cargo staticlib + swiftc → .app bundle
├── Info.plist                     # IMK 键名（参照系统/第三方输入法实测）
├── Resources/
│   ├── yinghuo.png / @2x.png      # 菜单图标
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

- macOS（本机实测 13.7 / Intel x86_64）；
- Xcode **或** Command Line Tools（含 `swiftc`、`clang`、`codesign`）；
- Rust 工具链（见仓库根 `rust-toolchain.toml`）。

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

`build.sh` 会把这些文件打进 bundle 的 `Contents/Resources/`：

| 文件 | 是否入库 | 缺失时 |
|---|---|---|
| `data/generated/wubi86-core.tsv` | ✅ 已入库 | 宿主回退内置样本引擎 |
| `data/generated/pinyin-chars.tsv` | ✅ 已入库 | 不启用拼音 |
| `data/generated/pinyin-words.tsv` | ⛔ 大文件不入库 | 拼音降级为单音节 |

复现大文件：

```sh
./data/sources/fetch-jieba-dict.sh        # 以及 fetch-pinyin-data.sh / fetch-phrase-pinyin.sh
cargo run -p ime-pinyin --example generate
```

## 手动装载（本机 macOS 27 验收通过）

ADR-023 修正后的经典 `.app` + IMKServer 已通过本机 macOS 27 装载验收：Developer ID 签名、公证、系统域安装、重启后，用户确认 TextEdit/Safari 的 `wq→你`、`nihao→你好` 正常。每次重新构建仍须重新签名/公证；`build.sh` 的 ad-hoc 产物用于开发校验。T-M3-03 将固化安装流程。

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

## 验证打字

1. 打开 TextEdit，切换到「萤火虫」输入法。
2. 打 `wq` → 候选窗出现 → 空格/数字上屏 → 得到「你」。
3. `kwwl` → 「中华人民共和国」；`nihao`（混输自动拼音兜底）→ 「你好」。
4. 退格删码、Esc 取消组合。

## 配置

- **唯一配置文件**：`~/Library/Application Support/萤火虫/config.toml`
  （宿主启动时经 `ime_config_init` 告知引擎，绝不使用 `UserDefaults`，见 `docs/配置架构.md`）；
- 首次运行前文件可以不存在 → 使用 Schema 默认值；改动后重新装载/重启生效。
- 切换模式：文本输入菜单里的「切换输入模式」（当前实现；正式交互属 P1-M4），
  或直接改 `config.toml` 的 `mode = "mixed" | "wubi" | "pinyin"`。

## 已知限制 / 待人工验证

- **装载与打字必须由人在真实桌面验证**：无头环境只能保证「编译通过 + 包结构正确 +
  可执行不崩溃」（本仓库已实测到这一步）。
- 候选窗为 P1-M3 最小实现：无翻页、无亮/暗主题自适应、不跟随光标滚动（属 P1-M4）。
- 未做通用二进制（仅当前架构 x86_64）。
- `CFBundleIdentifier` 暂用 `org.yinghuo.inputmethod.Yinghuo`，最终包名取决于 **TBD-4**。

## 为宿主扩展的 `ime-ffi` 入口（T-M3-02）

| 函数 | 作用 |
|---|---|
| `ime_session_new_with_data(wubi, chars, words)` | 从真实 TSV 创建会话（词表可空） |
| `ime_session_buffer(session)` | 借用组合缓冲区（预编辑串） |
| `ime_session_set_mode(session, mode)` | 切换模式 |
| `ime_session_key(...)` | 成功时返回 `IME_KEY_CONSUMED/_COMMITTED/_PASS_THROUGH` |
| `ime_config_init(path)` | 宿主设定唯一配置路径（须最先调用） |

全部入口仍 `catch_unwind` 兜底、坏输入返回错误码；真实 `unsafe` 只存在于 `ime-ffi`。
