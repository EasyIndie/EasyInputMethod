# 键位字根表 schema（key-roots v1）

供输入法练习/学习界面显示"编码方案的键位字根分布"。文件为 **UTF-8 TSV**，一行一键。

## 字段

| # | 字段 | 说明 |
|---|---|---|
| 1 | `scheme` | 方案标识，与文件名 `key-roots-<scheme>.tsv` 一致 |
| 2 | `letter` | 键位字母，大写 |
| 3 | `zone` | 区号：1 横 / 2 竖 / 3 撇 / 4 捺 / 5 折 / 0 无分区（万能键） |
| 4 | `keyname` | 键名字根（单个字，界面重点显示） |
| 5 | `roots` | 该键其它字根，空格分隔、**按使用频次降序**，不含键名本身；可为空 |

以 `#` 开头的行是注释。

## 约束

- 必须覆盖 25 个主键（`Q W E R T Y U I O P A S D F G H J K L X C V B N M`），可含万能键 `Z`。
- `letter` 不得重复；`roots` 不得重复、不得包含 `keyname`。
- 不含私用区（PUA）码位；不含 `？` 占位。
- 体积目标 ≤ 32 KiB（当前五笔 86 约 1.3 KiB）。

## 加一个新方案

1. 新增 `data/key-roots-<scheme>.tsv`（同 schema）。
2. 生成器：若方案数据来自本仓库教学资源，用 `tools/build_key_roots.py --scheme <scheme>`；否则手写并与上游许可一起登记。
3. 在 `data/sources.toml` 登记（derived 或外部来源 + 许可 + SHA-256）。
4. 调用方传 `KeyRootLayout.load(schemeID: <scheme>, displayName: …)`；**视图与测试无需改动**。

## 复用（其他项目）

`Sources/KeyRootLayout.swift`（数据模型 + TSV 解析）与 `Sources/KeyboardMapView.swift`（AppKit 视图）不依赖本仓库任何类型，
两份文件可直接拷走；只要 bundle 里有同名 TSV 即可工作，缺失时回落到"只有键名字根"的内置表。
