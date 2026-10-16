# 023：最终UI包B安装与登录前验收

2026-10-15。用户确认B空闲，按当前安装/验收请求继续。最终包提交50fdac31381f2adfeda02bf1954b414e54953ea2；ZIP SHA-256 54143060ac926934aa2f1e1595d48c33d2bcef07d94e4fa8bb6510314418c27b。

## 安装

- 原安装d429cec，当前源ABC；先备份配置/词库，再核对精确旧宿主PID/路径并发送TERM使其正常退出。原包移动至私有备份，最终包使用随包安装器dry-run及安装；未修改签名资源。
- 备份：`/Users/joker/Library/Application Support/Lampyris/acceptance-backups/ui-50fdac3-bqnepsnb`，其中原Lampyris.app与data/config.toml、data/user-dictionary.tsv及original.json可供恢复。
- 新安装：`/Users/joker/Library/Input Methods/Lampyris.app`，SOURCE-COMMIT=50fdac3，签名可执行文件SHA-256 `31badc4b53f5004d58b5c8e7674d1b5e34a5ac99b6d3846d2b3fa9078103902a`。
- 已装副本codesign deep/strict、stapler validate及Gatekeeper通过；完整启用集合、原输入源及真实配置/词库摘要保持。没有发布Release。

## 原生尝试

TextEdit normal两次均在自有文档创建阶段AppleEvent超时（-1712），尚未执行按键或marked range验证。源/启用集合恢复且数据完全不变。各次随后只读查询成功，使用本次独有文档名称、窗口ID和路径核验后精确关闭；其他窗口不动。失败不计通过，原日志保留。

两次选择正式模式后未观察到新版Lampyris宿主进程；不能把仅TIS选择成功视为IMK装载成功。安装器明确要求注销/重新登录；已请用户手动安排，不自动注销、不重启系统服务或关闭安全保护。尚未确认根因，重新登录后的结果决定后续处理。

证据：`/private/tmp/lampyris-final-ui-B-50fdac3/install-result.json`、textedit-suite.log、textedit-suite-retry.log、timeout-fixture-cleanup.json、retry-timeout-cleanup.json。UI04产品/UI05产品保持未完成，A暂缓，五日试用未开始。
