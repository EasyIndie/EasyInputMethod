# 报告 295：删除五笔码浮层（ADR-367）+ 数字串逗号保持半角（ADR-368）

日期：2026-11-17 / pi（air）· 分支：`dev`

## 1. 用户诉求

1. **拼音上屏后的「词 五笔 编码」浮层没有用、干扰输入**，要求去掉。
2. **中文模式默认中文标点**，只有用户明确要英文标点时手动切换。核对后确认：`punctuation = "chinese"` 本来就是默认值，
   唯一的"自动冒出英文标点"路径是 ADR-325 的 `input.digit_punctuation`，但这条规则只覆盖 `.` 和 `:`，
   于是同一串数字里 `3.14` 半角、`3,14` 中文，口径不一致。用户选择"补齐逗号"（B-b）。

## 2. 改动（两件都在删/收敛自动行为）

### 2.1 ADR-367：彻底删除五笔码浮层

| 文件 | 改动 |
|---|---|
| `platforms/macos/Sources/InputController.swift` | 删 `hintWubiCode(for:offered:)` 与三处调用；把**薄弱字记录**（ADR-335）抽成 `recordWeakChar(for:offered:)`，判定条件不变、不再渲染 UI |
| `platforms/macos/Sources/StateHUD.swift` | 删 `StateFeedback.wubiHint(text:code:)` |
| `crates/ime-config/src/schema.rs` | 删 `candidate.hint_wubi_code`（选项 34→33） |
| `crates/ime-config/src/lib.rs`、`crates/ime-ffi/src/config.rs` | 键表与 `layout.view.len` 断言同步 |
| `platforms/macos/Sources/Settings.swift` | 「五笔学习」组去掉该开关 |
| `platforms/macos/tests/settings-presentation.swift`、`controller-menu.swift` | 键表 / 行数 / 提示文案断言同步删除 |

旧配置里残留的 `candidate.hint_wubi_code` 按既有规则进 `last_unknown_keys` 并被忽略，下次写盘自然消失（不迁移、不报错）。

### 2.2 ADR-368：数字串里的 `.` `:` `,` 一律半角

| 文件 | 改动 |
|---|---|
| `crates/ime-core/src/lib.rs` | `matches!(key, '.' \| ':')` → `'.' \| ':' \| ','`；单测改为 `3.14` / `12:30` / `1,000` 全半角且数字外恢复中文 |
| `crates/ime-config/src/schema.rs` | 标题「数字后的 . : , 保持半角」，说明补 `1,000` |
| `docs/配置架构.md` | 示例行同步 |
| `tools/macos-probe/quality-samples.sh` | 样本「数字后逗号仍是中文（`3，`）」→「数字后逗号保持半角（`3,14`）」 |

## 3. 验证

| 检查 | 结果 |
|---|---|
| `make verify`（fmt/lint/test/deny/verify-no-network） | PASS，542 产物零网络符号 |
| `make macos-offline-tests` | **69 文件 / 340 例 PASS**（6 并发，46.8s） |
| `./platforms/macos/build.sh --strict` | PASS（ad-hoc，仅本地开发验证） |
| `make macos-ui-snapshots` | PASS（设置/关于/诊断/状态反馈离屏渲染，未显示窗口、未改真实配置） |
| `./platforms/macos/dev-preview.sh --smoke-test` | PASS（**CI 首跑红**：`Preview/main.swift` 仍断言 34 个设置项，改 33 后通过——离线回归不含预览冒烟） |
| `ime-core` 单测 | 31 PASS，含扩展后的数字串标点用例 |

## 4. 差异与遗留

- **未在已装包验证**：本轮只做了离屏与离线断言。浮层消失属"`grep` 为 0 + 编译通过"即可判定；
  数字串逗号需要真机按键确认（`3,14` / `1,000` / `12:30`，以及数字外的 `3,14。` 仍中文）。
- 与 ADR-365/366、报告 293/294 一起，等下一次 `dev → main` 的公证候选**一轮换包**做真机复验。
- `practice.collect_weak_chars` 行为不变：`weak-chars.tsv` 仍只在混输 + 拼音候选 + 单字 + 有码时记录。
