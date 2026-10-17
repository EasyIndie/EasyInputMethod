# 060 — 真实鼠标身份错配与父项动作单因素对照

2026-10-17，承接报告059。用户已手动恢复正式萤火虫并批准 v3，后又确认立即配合真实鼠标。A 未操作，产品源码未改，PR #53 仍草稿。

## v3 现场结果

候选 menu-distinct-siblings-v3，SHA 9d57a39f…fd3cca6；三种模式兄弟入口已不同，分别复用既有顶层叶项供服务校验。

1. 第一次鼠标对照在命中五笔后触发输入源/焦点守卫，停止，BLOCKED。finally 恢复包，但当时最终源审计被焦点门禁阻断；随后独立核验恢复为正式 PID13652、原模式/数据/TIS源及实际萤火虫栏，不能把最初恢复错误隐去。
2. 必要 AX 对照仍 mixed，收到 tag=6 混输项；关于阳性有效，FAIL。已恢复原正式包 PID14204、原数据/模式/TIS源，实际栏暂 ABC，如实记录。
3. 用户同意立即配合真实鼠标后，临时准备同一候选 PID14745，180秒超时自动恢复保护。此前已知 ABC/API差异，故此轮由用户建立真实菜单路径，没有把自动化原正式菜单门禁冒记为通过。用户明确回复“已用真实鼠标点击五笔”；实际配置和菜单父项仍 mixed，FAIL。

真实鼠标证据：

```text
MENU_SERVICE_TRACE layer=common phase=entered action=other input=dictionary item=number command=0 has_title=1 client=1 responds=1
MENU_ACTION_TRACE phase=entered format=dictionary item=item command=6 enabled=1 action=other decode=6 persisted=mixed session=mixed error=0
MENU_ACTION_TRACE phase=returned format=dictionary item=item command=6 enabled=1 action=other decode=6 persisted=mixed session=mixed error=0
```

本候选三个分组入口在静态日志中统一归类 other，不记录任意 selector；other 不是无效命令。decoder=6 表明实际解析混输，五笔应为7。本轮 session=mixed，排除了仅因冷控制器未激活而不切换。关于 reply/common 及阳性日志有效，不能再将本轮问题仅归为 AX/合成鼠标或重复兄弟 selector。具体生成错误菜单身份的函数仍未确定。

三个模式和顶层保护没有全部完成，不把首项失败升级为整套验收。证据 `build/menu-distinct-siblings-20261017/live-b-attempt01/02` 及 `live-b/`；后者保存用户完成标记、human-mouse-receipt-trace.txt、result.json、final-audit.json。

## 已完成恢复

真人测后同次 finally 恢复 a5d456b 正式包 PID15444（下次重读），执行 SHA ed2a2ea…ea96c1；strict签名通过。mode=mixed，配置/词库字节、TIS原源及完整集合不变，**本轮通过系统菜单恢复，实际栏也为萤火虫**，恢复错误为空。没有文字/剪贴板诊断、词库覆写、全量包/数据备份、新权限或重启；其它窗口保留。

## 父项标志的四组隔离对照

独立、未注册 IMK 仅改变父项自定义action和view两个布尔量：

| 自定义action | view | 框架最终父项selector | parent-selectable | 子项数 |
|---|---|---|---|---|
| 无 | 无 | submenuAction: | 0 | 3 |
| 无 | 有 | submenuAction: | 0 | 3 |
| 有 | 无 | cycle: | 1 | 3 |
| 有 | 有 | cycle: | 1 | 3 |

证明该标志由自定义action触发，而不是view。**尚不证明它就是实机错配原因。** AppKit 为标准子菜单父项自动设置 submenuAction:，所以“无自定义action”不等于最终action指针为nil；初次诊断断言错误已纠正，失败记录保留。

证据 `build/menu-surface-audit-20261017/parent-flags*.{m,txt}`。历史标准父项实验因模式主动禁用没有有效选择结果（报告050），不能当成这个新对照已经被否定。

## v4 已准备、未现场运行

menu-parent-action-v4，SHA `d8d03c9a39f6dfb2ae14b6a0e6b96129b7e6b2af0296f3a5e25ce42a57aacfe8`，arm64、adhoc本地签名、未公证。独立 `build/menu-parent-action-control-20261017/`。

与 v3 仅一行源差异：父项不绑定自定义循环action，让 AppKit 使用标准 submenuAction:，因此 parent-selectable=0；其它入口分组、tag、层级、文字、view、四层包装及静态日志不变。诊断中父项点击循环暂时不可用，**不代表产品已采纳取消循环的交互**。

三模式/四状态、冷选择/重激活及身份保护的生产优化隔离回归通过，12次服务配对、113行白名单/哨兵隐私通过，编译/八个保护工具零诊断，codesign strict通过。父项测试明确校验系统submenuAction:，没有虚报原父项循环通过。初次生成脚本引号错误及错误nil断言记录保留。

保护驱动已准备，尚未采基线。拟先自动化五笔，成功才继续其余模式/冷顶层保护、关于阳性，必要时真实鼠标；同次恢复原正式包/当轮状态。不新增可见项或额外用户路径，不输入文字、不改权限、词库或建立备份。具体新候选运行及B空闲确认待；用户仅批准v3，未将其扩成v4安装许可。

产品四状态激活会话、父项循环/保持菜单、右对齐及正式输入验收仍待，不能由本地回归或此前CI绿色关闭。

本轮产品源码未改，提交前make verify全绿、176产物隐私断言通过；新诊断候选的独立生产优化编译和回归另行留痕，不用项目门禁替代其现场验证。
