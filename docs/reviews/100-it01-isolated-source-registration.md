# 100 — IT-01：独有身份包注册 / TIS 枚举（A 机）

2026-10-19，A（Intel / macOS 13.7.8）。目标是证明「独有身份（`cn.jokerhub.inputmethod.LampyrisIMKTest.<UUID>`）」
的输入法能被系统注册并被 TIS 枚举，为后续 IMK 隔离验收铺路。全程不启用、不选中、不发键。

## 结果

| 方式 | 命令 | 结果 |
|---|---|---|
| **软链**别名 | `run-isolated-source-probe.py <root>` | **BLOCKED**：`lsregister` 扫描软链失败 `-10811`；清理 `lsregister -u` 亦失败 → 脚本按设计保留资源 |
| **实体包**对照 | `run-physical-source-probe.py <root>` | **PASS**：`physical registration: 2 owned sources`（父身份 + `.default` 模式），随后删除自有实体包，**原输入源与启用集合不变** |

- 软链留下的一项副作用已人工清理（只删本次自建的 `~/Library/Input Methods/LampyrisIMKTest-07bd….app` 软链），
  现在该目录只剩 `Lampyris.app`。
- 证据：`platforms/macos/build/acceptance-it01-a/`（`05-isolated-source.txt`、`06-physical-source.txt`、
  `launchservices-recognition.json`、`register-physical.json`、`physical-ls.json`、`state-*.json`）。

## 本轮修的工具问题（都不是产品代码）

1. `isolated-imk/source-state.swift` 用了异质字典字面量，**Swift 5.8.1 编不过**（`heterogeneous collection literal`）→
   显式标注 `(source: TISInputSource) -> [String: Any]`，Swift 5.8 与 6 都能编。
2. `isolated-imk.py` 新增 `LAMPYRIS_IMK_TEST_OPT`（默认 `-O`）：A 上即使 `-Onone`，构建隔离宿主仍要 **14 分 22 秒**
   （机器负载 + 老工具链），慢机器用 `LAMPYRIS_IMK_TEST_OPT=-Onone` 跑协议/注册类验证；性能结论仍以 `-O` 为准。

## 结论与影响

- **macOS 13/A 上：软链注册不可行，实体包注册可行且可枚举**（2 个自有身份），清理后用户输入源集合不变。
  因此后续「独有身份包 + 真实 IMK 输入」应走实体包路径（与 ADR-119 的物理对照一致）。
- IT-01 仍不关闭：下一步是把实体独有包**安装/启用**后跑 `run-installed-textedit-probe.py`（真实 IMK 输入 + 恢复），
  以及 Safari/Terminal 原生协议、完整剪贴板恢复、微信草稿（BLOCKED）。
