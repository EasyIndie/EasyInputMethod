# 040 用户界面验收后的候选收口预检

2026-10-16。用户明确“验收完成，继续推进其它事项”，记录为报告039本轮预览界面验收；不扩写为真实IMK/VoiceOver或整体MVP通过。冻结代码a5689def36e34265e2d9ea6d9e9a3f34898148e5，独立工作树codex/menu-state-shortcuts；主目录原有产品修改不覆盖。

## 本轮完成

- PR #45精确head的check/dco/fuzz/macos四检查全部SUCCESS，CI38902167497；mergeable/MERGEABLE、mergeState/CLEAN，base1621a6d。
- 本地完整离线回归26文件85项全部通过，包含近期设置基线/按钮、模式/预览同步及打包/数据保护；此前关于“完整矩阵为前轮证据”的限制已由本轮冻结head重跑补齐。
- 本地universal审核包及含锁定vendor依赖的配套源码包生成；共用validate-release.py --review通过摘要、版本/提交、实际双架构、包内完整清单、离线材料和许可资料核验。
- 从配套源码完全离线重建成功，去签名可执行文件及默认输入数据逐字节一致。这是代理同环境工程重建，不替代用户独立核验。
- PR #45已从草稿转为ready for review；合入请求被自动审批拒绝，未执行。已请求用户明确批准“合入main并触发CI签名公证”，不包含安装或Release。等待期间保持a5689de head，不把这份新报告提交推进待批准SHA。

## 审核附件（不是可安装的正式分发包）

持久保存在主目录platforms/macos/build/menu-rc-a5689de-review/candidate-O2MLwi：

| 附件 | 字节 | SHA-256 |
|---|---:|---|
| Lampyris-0.1.0-universal.zip | 4,928,940 | 5b5ee0b38ae3a23dd47e841a4952380d9d798b36d1cf94a45eef943692854904 |
| Lampyris-0.1.0-source.tar.gz | 13,049,098 | c199ef611521480e47d1570b13561e0dd772865e7ebbf50d4c9c82972ffc143c |

二进制ZIP低于15,000,000字节；源码包单列，不把源码和二进制体积混算。去签名可执行文件SHA为d28febca0e5b5452c0ec4788ab220f900e8dd5edb19e4112c5f37082687f6e10。正式CI的Developer ID签名/公证候选尚未生成，不能拿本ad-hoc审核包安装或做信任结论。

完整证据：同级evidence.json、offline-summary.json、offline/prepare/repro/ffi-perf.log及四份附件。根工作树packaging/out/candidate-O2MLwi有原始副本。

## IT-12参考子步

冻结版本运行run-perf.sh 1 --max-user-dictionary：临时配置、最大容量合成词库、单会话、2200按键；p50 0.123ms、p95 0.932ms、max 9.088ms；peak RSS 28.72MiB、steady physical footprint 24.34MiB；单次提交学习1.725ms，focus_out后24.80MiB。测试根自动清理，没有读取或写入真实词库。

该探针仅包括ime_session_configure/key等纯FFI调用，不包括IMK派发、候选窗口、客户端或合成器；内存属于该C探针，不能当宿主≤30MB通过证据，也不把MiB与MB混用。真实IMK的冷启动/简繁首次/多客户端/长组合/CPU/唤醒仍需安全桌面场景与最终包，IT-12未关闭。本轮没有运行会显示候选窗口的render-perf脚本。

## 自动审批阻塞与下一步

自动审批明确拒绝gh pr merge 45 --merge --match-head-commit a5689…：理由是合入受保护默认分支会变更远端历史/代码状态，审核认定现有授权仅覆盖推送与草稿PR，未明确涵盖此次合并，并引用此前“暂不合并”边界。没有通过API/其他命令绕过，也没有重复提交相同请求。

用户明确批准后，重新核对精确head和四检查，正常合入并等待既有main工作流生成签名/公证/离线重建附件；随后核验正式附件身份与Apple信任。安装与实机输入仍要另行确认设备空闲及安装安排。B保持1621a6d，未切源/发键/启用VoiceOver/安装/发布，自建结构库仍MVP后。

## 后续范围更新

用户最新要求先本地自动化，旧merge审批询问被覆盖；合入、公证和安装暂停。本地逐场景结果及正式未测边界见报告041，未执行merge。
