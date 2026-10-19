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

## 追加：安装独有包后让它在系统设置里可添加 —— BLOCKED（本机缺 Developer ID）

尝试把实体独有包装进 `~/Library/Input Methods/`（`LampyrisIMKTest-86bde0d0….app`，已 `lsregister -f`），
结果 System Settings 的「＋」列表里**看不到**它，用户无法添加。查明的直接原因：

| 检查 | 结果 |
|---|---|
| 签名 | `Signature=adhoc`、`TeamIdentifier=not set` |
| Gatekeeper | `spctl -a -vv` → **rejected** |
| 本机签名身份 | `security find-identity -v -p codesigning` → **0 valid identities**（无 Developer ID 证书） |
| TIS | 父身份与 `.default` 模式**已枚举**（`enableCapable=true`），但 `TISEnableInputSource` 仍返回 0 不生效；启用列表中没有它 |

结论：**不是缓存/重启问题**；ad-hoc 签名 + 本机无 Developer ID 的输入法不会出现在「＋」列表里。
因此「实体独有包 → 真实 IMK 输入」这一子项在 A 上 **BLOCKED（缺签名能力）**，已清理临时 app 与私有根，
用户输入源集合与真实数据未受影响（`tools/macos-probe/bin/tissrc list` 复核）。

可选后续（择一）：
1. 由 CI 产出「隔离身份 + Developer ID 签名」的包，再在 A 上安装验证（需一次注销）；
2. 在 A 导入 Developer ID 证书（.p12）后本地签名重试；
3. 接受报告 099（**已装正式包 + 私有数据根**）作为真实 IMK 输入证据，把本子项记为 SKIP/BLOCKED（缺签名），
   在发布前用 IT-14 的签名包补验。
