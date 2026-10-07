# data/

词典/码表/词表源数据。**任何数据进入这里之前，必须先读 `.agents/skills/add-data-source/SKILL.md`。**

- `sources.toml` — 机器可读的来源登记（URL / 上游 / 许可 / SHA-256 / 用途）。
- `sources/` — 小体积源文件；大文件用 `fetch-*.sh` 下载脚本代替提交。
- `wubi86/`、`wubi98/`、`wubi-new/`、`pinyin/` … — 各方案源数据。

规则（见 `docs/数据来源与许可.md`）：

1. 只接受与 **GPL-3.0** 兼容的许可；
2. 每份数据必须在 `docs/数据来源与许可.md` 和 `data/sources.toml` **双重登记**；
3. 优先"自建生成"（我们的编码器），而非复制第三方派生物；
4. 对"第三方重新授权/上游不明"的数据打 ⚠️，且不得作为不可替代来源。
