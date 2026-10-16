# 028 完整UI与学习最终包设备B安装

2026-10-15。用户确认“B空闲”，继续已安排的安装及验收；最终提交1621a6d5013cbab8cc0d95a5f89c17c5d40b6166，执行文件SHA256 296a698c0a51ff43eac29ace4800aef5826be8eb1295204ca08fe047ca9097ec。

## 安装与保护

- 原源ABC。精确核对旧宿主PID983的实际可执行路径后发送TERM，观察其正常退出；没有广泛kill、重启系统服务或自动注销。
- 私有备份：`/Users/joker/Library/Application Support/Lampyris/acceptance-backups/ui-1621a6d-p61kfl7t`。保存旧50fdac3包、配置/词库、完整源快照与摘要；备份在持久Application Support内。
- 使用核验过的包内安装器安装；已装副本摘要、codesign深度严格、stapler与Gatekeeper通过。配置/词库摘要、原输入源及完整启用集合均保持。

## 加载前置

UI脚本查询true。短时精确选择正式源，6秒内没有观察到新Lampyris宿主进程；已恢复ABC及完整启用集合，再次核对真实数据不变。未创建测试文档或发送任何按键。TIS选择成功不计为IMK加载或产品验收通过。

按安装器要求等待用户手动注销后重新登录或重启，再确认新宿主加载并推进真实输入/学习交互。不自动注销用户，也不重复发起TextEdit超时探针。

证据：platforms/macos/build/final-ui-1621a6d/install-result.json、host-load-result.json及installed-*.log。实机UI/VoiceOver/A和五工作日仍待，未发布Release。
