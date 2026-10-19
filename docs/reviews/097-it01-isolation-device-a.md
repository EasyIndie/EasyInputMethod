# 097 — IT-01 隔离验收（A 机）：原生 TextEdit 所有权协议通过 + 工具链差异

2026-10-19，A（Intel / macOS 13.7.8）上推进发布门禁 **IT-01（实机验收数据保护 / 文件隔离）**。
只使用探针自建的临时文档，未触碰用户真实文档、配置或输入源。

## 结果

| 项 | 命令 | 结果 | 证据 |
|---|---|---|---|
| 原生 TextEdit 唯一文件对象协议（正常路径） | `run-owned-probe.py normal` | **PASS** | `04-owned-after-fix.txt` |
| 同上（注入失败路径，失败保留自身证据） | `run-owned-probe.py failure` | **PASS** | 同上 |
| 共享所有权四路径（normal/failure/INT/TERM） | `run-owned-library.py` | **PASS（4/4）** | 同上 |
| 探针后环境 | `osascript … count windows` | TextEdit 窗口 0，无残留 | `04-owned-after-fix.txt` |
| 离线回归（该协议） | `test-owned-probe.py`、`test-owned-resources.py` | PASS | 终端输出 |

### 本轮修的问题（macOS 13 语义）

首次运行两条路径都报：

```
-1700 不能将“visible of window id 2728 of application "TextEdit"”转换为“boolean”类型
```

原因：macOS 13 上 `close testDocument saving no` 会**直接销毁窗口对象**，随后再查询 `visible of window id testID` 不是返回 false 而是抛错 ——
探针把“成功关闭”误判成“清理失败”。修法（`probe-owned-textedit.applescript`）：先 `exists window id testID` 再判 `visible`，
等待循环与最终断言都加这层保护（与 ADR-091 对 installed-textedit 探针的处理一致）。修后两路径与四路径全通过。

## 仍未关闭（保持 BLOCKED / 未验证）

| 项 | 状态 | 说明 |
|---|---|---|
| IMK 学习数据隔离（真实宿主学习写入隔离） | **BLOCKED** | `run-imk-acceptance.sh` 仍按设计 `exit 3`；需要独有身份包 + 隔离学习目录的证据 |
| 独有身份包注册 / TIS 枚举 | **BLOCKED** | 设备 B 历史记录：识别/注销成功但 TIS 未枚举；A 未重跑 |
| Safari / Terminal 原生协议 | **未执行** | 需要各自的隔离草稿/窗口脚本；当前先做 TextEdit |
| 完整剪贴板（多类型）与输入源恢复的实机证据 | **部分** | 命名剪贴板与脚本级恢复已有 mock；真实通用剪贴板仍需隔离条件 |
| 微信聊天隔离草稿 | **BLOCKED** | 无安全隔离草稿，不投递按键（沿用既有结论） |

## A 机工具链差异（影响验收方式，不影响产品代码）

`make macos-offline-tests` 在 A 上 **13/31 失败**，两类原因：

1. **Swift 5.8.1 编译不了部分测试**：`candidate-presentation` / `input-menu` / `preview-menu` / `settings-presentation` /
   `tools-presentation` 等用了异质字典字面量（`[String: Any]` 推断），Swift 5.8 报 `heterogeneous collection literal`；
   CI 的 Swift 6.3.3 正常。**不是产品缺陷**，属工具链差异。
2. **编译超时**：系统负载 18–21 时 `swiftc`/`clang` 超过测试内 45–90 秒上限（同一命令单独跑 2–3 秒即过）。

结论：**A 上用 CI 作为 Swift 侧门禁**；本地只跑与 Swift 5.8 兼容的部分（Rust `make verify`、Python 离线回归、原生探针）。
这条已写入 `HANDOFF §3` 与技能 `iterate-macos-ime`。

## 结论

IT-01 的**原生对象所有权协议在 A 上首次拿到真实通过证据**（此前只有 mock 与 B 机结果），并修掉一个 macOS 13 语义问题；
其余子项（IMK 学习数据隔离、独有源注册枚举、Safari/Terminal 协议、完整剪贴板、微信草稿）仍 BLOCKED，IT-01 不关闭。

证据目录：`platforms/macos/build/acceptance-it01-a/`（本地，不入库）。
