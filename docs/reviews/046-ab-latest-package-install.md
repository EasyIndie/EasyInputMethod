# 046：A/B安装同一最新正式包

2026-10-17。用户明确确认当前账号升级/设备B空闲，随后要求AB一起安装最新包，并明确A工作已保存、当前空闲。按ADR-196在已有账号操作，无新测试账号。

## 安装结果

两台均安装正式候选`abdb83ff2a6ff3cd1a63a48e0c446822e18e2f86`，来自签名公证运行38934284869。已装universal执行文件SHA均为`c4a0703481b56806fd454d0d301874916f82b5685a8a65c0af978ac61b093151`。

| 设备 | 账号 / 系统 | 原提交 | 最新包安装及Apple信任 | 新宿主观察 |
|---|---|---|---|---|
| A | bot / Intel / macOS13.7.8 | d429cec714067adba9ca7a362297f6e9fe38b545 | 通过 | 选择源后6秒未观察到，等待重新登录 |
| B | joker / arm64 / macOS27.0.1 | 1621a6d5013cbab8cc0d95a5f89c17c5d40b6166 | 通过 | 选择源后6秒未观察到，等待重新登录 |

逐台核验正式包SOURCE-COMMIT/摘要/Developer ID/票据/Gatekeeper；检查原源为ABC及已装旧SHA，精确校验旧宿主可执行路径后TERM，仅处理本次已知旧宿主。保存原安装、输入源集合和配置/词库备份后调用包内正式installer，核验已装副本。正常安装及短暂源选择观察后，两台原源ABC、完整启用集合、配置/词库摘要均保持。未发键、未创建或关闭用户文档、未自动注销或重启，也未重复安装已是新版本的副本。

## 持久备份

- A：`/Users/bot/Library/Application Support/Lampyris/acceptance-backups/ui-abdb83f-23blh0z2`，保存在A；包含旧Lampyris.app、配置/词库原文件及摘要、原源状态。
- B：`/Users/joker/Library/Application Support/Lampyris/acceptance-backups/ui-abdb83f-bkoogx9r`，保存在B；同样包含旧包及数据恢复基线。

备份是恢复材料，不授权盲目覆盖后续用户修改。A准备根为`/private/tmp/lampyris-abdb83f-z0eWdzBQ`，可在重启后失效；关键安装结果、信任日志和源恢复结果已复制到B的持久项目证据目录，旧包/数据备份不依赖临时目录。没有复制A用户配置/词库内容到B。

## 证据与边界

主目录`platforms/macos/build/final-menu-abdb83f/device-a-upgrade/`和`device-b-upgrade/`分别保存安装结果、源状态、信任日志与宿主观察结果；汇总为`ab-upgrade-summary.json`，完整文件SHA见evidence-manifest.json。

B最初在受限沙箱内调用TIS/pgrep得到系统服务错误，未据此改变安装或输入源；随后在已获授权的真实会话中只读重新核验，得到完整源集合和精确宿主身份后才升级。该预检错误不是产品失败。

安装后仅尝试选择已启用的同一输入源，观察6秒，随后精确恢复原源；两台均无新宿主，状态AWAITING_RELOGIN。没有把TIS选择成功当作加载或实际输入通过。A新宿主实际映射校验逻辑已准备，但未观察到进程，不能记运行成功。

正式schema2仍为包级1PASS、22BLOCKED；A/B安装与信任通过不等于平台使用/输入/菜单/学习/VoiceOver通过。CI同工具链源码重建通过与B跨SDK比较失败仍保留，详见报告045。

## 下一步

请用户分别重新登录或重启A、B，确认新会话可保持空闲；不需要重装。之后先只读核对新宿主精确身份/执行映射和权限，再用自建文档逐步进行真实输入、恢复、菜单与学习区测试。不得复用重登录前的空闲或源状态快照，不自动操作登录界面。

## 备份清理后续更新

用户2026-10-17明确不保留备份并要求全部清理；A上述1份、B上述最新1份及此前ui-1621a6d-p61kfl7t/ui-50fdac3-bqnepsnb共3份已删除，空acceptance-backups根亦已移除。当前安装/SOURCE-COMMIT/现用配置词库前后SHA不变。本文备份路径仅为安装历史，不再可用；清理结果见final-menu-abdb83f/backup-cleanup/a.json与b.json。后续不自动重新创建全量备份。
