# 249 — 预览冒烟红灯的根因：`z` 是通配符，测试夹具用了 `zz`

- 日期：2026-11-06　｜　触发：PR #226 的 `macos` 作业 `预览冒烟失败：预期 离线测试词，实际 他`
- 结论：**不是产品回归**，是 1.2.0 的二级简码入表后，旧的测试夹具代码 `zz` 变成了通配符查询。

## 1. 现象

- `./platforms/macos/dev-preview.sh --smoke-test` 在 dev 失败，在 `main`（origin/main worktree）通过。
- 失败点：`view.clear(); keys("zz "); check("离线测试词")` —— 期望上屏用户词条，实际得到 `他`。
- 探针打印：输入 `zz` 时候选为 **他 / 组织 / 政治**。

## 2. 根因

`CodeTableEngine::convert` 里：

```rust
let wildcard = self.z_wildcard && input.contains('z');
```

五笔的 `z` 是**通配键**（配置项 `z_wildcard`，默认开启）。所以 `zz` 从来不是字面代码，
而是"任意 2 码"的通配查询：

| 分支 | 码表里 2 码行数 | `zz` 的结果 |
|---|---|---|
| `main`（1.1.0） | **0** | 通配无命中 → 只剩用户词条 `zz` → 测试通过 |
| `dev`（1.2.0 二级简码 598 条） | 598 | 通配命中大量真实码（`wb`=他 等）→ **用户词条被码表候选盖住** |

也就是说：测试夹具用 `zz` 只是"随便找个空码"，恰好撞上了通配语义；1.2.0 把 2 码行补上后，
"空码"不再空。

## 3. 处置

把夹具换成语义明确的 4 码（`aowo`，实测码表中**没有任何码以它开头**，也不含 `z`）：

- `addWord(scheme: "wubi", code: "aowo", …)`；
- `keys("aowo ")`；
- 重启后重放改为按字符喂 `aowo`（原来硬编码 `feed(122)` 两次）。

改后 `dev-preview.sh --smoke-test` 通过。

## 4. 附带确认的行为（不是缺陷）

- **用户词条代码含 `z` 时不可达**：`z` 是通配符，`zz`/`zabc` 这类输入永远走通配分支。
  这是既有设计（`z_wildcard` 配置项），不是 1.2.0 引入；只是以前没人踩到。
- 若将来要支持"以 z 为字面代码"，需要另立 ADR（例如要求 `zz` 只在特定模式生效），当前不做。

## 5. 复现

```sh
# main 通过、dev 失败（1.2.0 数据）
git worktree add /tmp/main-wt origin/main
cd /tmp/main-wt && ./platforms/macos/dev-preview.sh --smoke-test   # ✅
cd - && ./platforms/macos/dev-preview.sh --smoke-test               # 改前 ❌ / 改后 ✅
```

## 6. 关联

报告 238（二级简码入表）、`crates/ime-table/src/lib.rs` `convert()`、`platforms/macos/Preview/main.swift`。
