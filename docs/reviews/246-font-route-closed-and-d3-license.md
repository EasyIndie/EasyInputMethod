# 246 — 字形字体这条路是关的（而且顺手查出 D3 的许可登记是错的）

- 日期：2026-11-06　｜　关联：报告 241/245、ADR-016/189/309
- 结论：**字体路线不可用**（两款候选字体都"未附带任何版权声明或许可证"），
  且发现 `data/sources.toml` 把 D3 记成 MIT 是**错的**，必须降级为"不可分发 oracle"。

## 1. 想查什么

报告 245 的 249 条占位字根要靠"能给出字根字形身份"的来源。候选两条：

1. **D3 上游的字体** `data/schemas/wubi86/HeiTiZiGen.ttf`（"黑体字根"，渲染 PUA 字根用）；
2. **D2 上游的字体** `wubi-lex-etymon-v5`（aardio 运行时下载，注释说"参考 yanhuacuo/qingg 增删修改"）。

思路是：字体 cmap 定位字形 → 轮廓与已知 Unicode 字根比对 → 得到 PUA 的身份。

## 2. 实测结果

### 2.1 HeiTiZiGen.ttf（D3）

| 项目 | 事实 |
|---|---|
| 大小 / SHA-256 | 61,416 B / `e8853ac6584fe43f…` |
| cmap 条目 | 687（其中 **BMP PUA 671 个**，U+9FB0 区 9 个） |
| 是否含**补充区** PUA（U+F00xx） | **不含** |
| 是否含常规汉字 | 不含（只有 9 个兼容区字形） |
| 字形名 | `uniE816` 这类编号，**没有字根名** |
| 许可 | 上游 `NOTICE.md`：**"未附带任何版权声明或许可证信息"**，来源"五笔输入法资源网盘，原始来源及作者不详" |

**致命点**：我们阻塞的 72 个占位字形**全部来自 D2 的补充区私有码位（U+F00xx）**，
这个字体根本没有这些码位——就算许可干净也用不上。

### 2.2 wubi-lex-etymon（D2）

| 项目 | 事实 |
|---|---|
| 位置 | 不在仓库里；运行时从 `http://wubi.aardio.com/download/spelling/fonts/wubi-lex-etymon-v5.lzma` 下载（实测 301→HTTPS，85,874 B 可下） |
| 来源 | aardio 源码注释：**"字体参考 https://github.com/yanhuacuo/qingg 进行了增删修改"** |
| qingg 许可 | **无**（GitHub API `license: null`） |
| 可复现性 | 个人域名、无版本号、无 SHA-256、无归档 |

两条都过不了 ADR-309 的准入门槛（可追溯 URL + SHA + 明确许可），**字体路线关闭**。

### 2.3 顺带查出的登记错误

`huanfeng/WindInput` 的许可沿革：**v0.127.0 之前是 MIT，之后代码改为 GPL-3.0-or-later**；
而我们用的 `wubi86_chaizi.txt` 与该字体，按上游 `NOTICE.md` 属于**"未附带许可证"**的第三方资源。
`data/sources.toml` 与 `docs/数据来源与许可.md` 都记着 D3 = MIT —— **这是错的**，风险等级应从"低"改为"高"。

## 3. 处置

1. **D3 降级**（ADR-310）：许可改为"未声明"，风险"高"，状态"仅作构建期 oracle，不分发"；
2. **B0 不再用 D3 作组件来源**：`--d3` 从 B0 生成命令里去掉，`componentsSource` 只剩 `D1`/`D2`；
   影响 33 条（多为变 partial，其中 8 条是 D2 自身漏拆、此前由 D3 兜底），
   最终 `full` 737 → **735**、`partial` 257、
   识别码 624、占位 243 条。
   这是干净溯源的价格，值得付。剩余 8 条（没、城、余、代、件、凭、俄、浠）D2 只给出 1–2 个字根，
   需要一份许可干净的第三方拆字数据才能补，暂按 `partial` 如实标注。
3. `pua-map.json` 仍是 D2↔D3 对齐学出的构建期产物，**不随产物分发**，文档写明；
4. 249 条占位**保持不变**（`？（键 h）`），不猜。

## 4. 为什么不再试"上下文推断"

用 IDS 叶子减去已知分量、再跨字投票来猜占位身份，实测投票极不稳定
（同一字形最高票 5 次、次高 2 次、还有 1 次的），等于猜。ADR-309 的口径是"宁可少说"，
所以这条不做。

## 5. 复现

```sh
# 字体检查（不写仓库）
curl -fsSL https://raw.githubusercontent.com/huanfeng/WindInput/main/data/schemas/wubi86/HeiTiZiGen.ttf -o /tmp/heiti.ttf
shasum -a 256 /tmp/heiti.ttf   # e8853ac6584fe43feffeb6263164a69950fec84e536fc28314fb43d5cb391d24
curl -fsSL https://raw.githubusercontent.com/huanfeng/WindInput/main/NOTICE.md
# B0 只用授权清楚的来源重新生成
cd modules/hanzi-structure && python3 tools/build_b0.py --codes ../../data/generated/wubi86-single.tsv \
  --radicals ../../data/sources/wubi-lex-86.txt --pua-map corpus/pua-map.json \
  --readable-keys ../../data/learning/wubi86-readable-keys.tsv --ids ../../data/sources/ids_lv1.txt \
  --short1 ../../data/sources/wubi86-level1-codes.tsv --short2 ../../data/sources/wubi86-level2-codes.tsv \
  --pinyin ../../data/generated/pinyin-chars.tsv --limit 1000 --out-dir corpus
```
