# 059 — 实机命令已送达，但五笔被解析成混输

2026-10-17。用户回复系统菜单能看到萤火虫后，重新只读核对，AX 状态栏也已显示萤火虫；精确自建 TextEdit 文档下展开原正式菜单，取得萤火虫、模式父项、三个子项、四状态和关于条目。报告058的两轮门禁失败仍保留，但“AX 列表没有条目”不能提升为真实入口持续缺失，更不能提升为系统不支持。

## 同一 v2 候选的有效现场结果

继续使用用户已批准的 receipt-trace-v2，执行 SHA c113c95b…ef2d32b，没有扩大包装范围。新采原正式 PID10607 和数据基线，先验证正式产品菜单可用，再临时替换候选 PID12188。驱动补了选源后实际状态栏就绪检查，而不是只在 ABC 下反复找入口。

鼠标准确命中可见“五笔”，前后两次 AX 命中核对通过；mode 仍 mixed。随后一次 AX 五笔对照也仍 mixed。两种路径的日志一致：

```text
MENU_SERVICE_TRACE layer=common phase=entered action=shared input=dictionary item=number command=0 has_title=1 client=1 responds=1
MENU_ACTION_TRACE phase=entered format=dictionary item=item command=6 enabled=1 action=shared decode=6 persisted=mixed session=none error=0
MENU_ACTION_TRACE phase=returned format=dictionary item=item command=6 enabled=1 action=shared decode=6 persisted=mixed session=none error=0
```

顶层关于阳性对照有 reply/common 入口及 `MENU_CONTROL_TRACE phase=about`，包装确实覆盖本轮系统菜单链路。结果为 **FAIL，诊断证据有效**。不是命令未送达，不是配置写入被拒绝：目标五笔应解码为 tag=7，而实际收到 tag=6 的混输项，代码因此继续选择 mixed；error=0 没有触发配置错误。

入口的数字 command=0 与控制器收到的 NSMenuItem tag=6 是两个不同层面的编号，不能混为一谈。控制器日志 session=none，不能把代理显示四状态启用当成已有真实文本会话。公共 doCommand 覆盖日志没有出现，但私有统一 action 已被实际调用，不能以公共覆盖未进推断动作未到。

本轮没有记录原始回传标题，故还不能仅凭这份日志确定系统最初发的是哪个标题，或精确到哪个系统函数构造错身份。可靠结论是：错误已收敛到菜单项身份构造/回传/解析链，当前统一 selector 候选不成立；不能宣称所有原正式包问题的根因已完整查清。

## 隔离回放及旧测试缺口

未注册真实 IMK、独立配置/词库中回放四种数字编号（0、1、500、501）及五种预设标题类别。提供正确五笔标题时四种编号均解码五笔；提供混输标题时均解码混输。父项标题触发原父项循环；空标题落到禁用/非命令项；缺标题且编号500/501时框架会抛越界异常。首次实验异常中止原始结果保留，补全矩阵通过捕获实验异常记录结果，不改产品或系统实现。

因此原服务回归人工提供正确目标标题，只覆盖了“收到正确身份后可执行”，没有覆盖本轮真实客户端错误身份。不能通过调整测试的数字编号，把旧回归包装成已经涵盖此错误，也不把私有 IMKMenuTitle 键引入产品。

证据：`build/menu-surface-audit-20261017/replay/` 保留首次中止，`replay-complete/` 保留20组完整结果；`build/menu-receipt-trace-20261017/v2/live-b/` 保存此次现场，前两轮在 live-b-attempt01/02 中。

## 待实测的最小诊断候选

ADR-203 仅作为研究假设：三个模式兄弟项使用不同公开 selector，并分别复用既有中英、宽度、简繁叶项入口供 IMK 服务校验；仍以 tag 加匹配 selector 解码。没有增加可见行、隐藏项或额外点击。必须实测排除顶层项反向误识别成模式，不能由静态映射推断安全。

独立构建目录 `build/menu-distinct-siblings-20261017/`；候选名 menu-distinct-siblings-v3；SHA `9d57a39fe93086d8e2cea05e11c65d4c6791491c46068927c8c7dcfb8fd3cca6`。arm64、adhoc 本地签名、未公证；本报告准备后用户批准，已完成临时实测并恢复原正式包，结果见报告060，**产品源码未改**。与 v2 的变化只有独立 InputMenu/InputController 副本中的入口分组、三个转发函数与 tag/selector 匹配；四层包装源码与 ABI 不变。

生产优化真实控制器回归通过：三模式、四状态、冷控制器/重激活；新增兄弟入口唯一、既有叶项覆盖、原八行/三子项数量不增及错误 tag/selector 拒绝断言。12次服务配对、119行日志白名单及哨兵隐私检查通过；编译/八个保护工具零诊断，codesign strict 通过。它仍只证明隔离服务和本地结构，不能证明真实客户端已纠正。

准备时现场范围：先验证原正式菜单，临时运行 v3，三模式逐项鼠标，首个失败必要时一次 AX 对照；全通过才做三个冷控制器顶层身份保护检查，再做关于阳性。冷检查只在 session_present=0 时执行，模式基线刻意与潜在错误目标不同；检查顶层项不会误写 mode，不把冷检查叫作四状态功能验收。不发文字、不点复制诊断，同次 finally 恢复原正式包/当轮状态。新候选改变命令路由，后续已取得单独许可；实际中断、真人选择及恢复记录见报告060。

## 恢复与未决项

v2 测后原 a5d456b 已恢复，PID12233（此为历史断点），执行 SHA ed2a2ea…ea96c1。mode=mixed，配置和词库字节均未变，TIS 当前源和完整启用集合恢复，恢复错误为空；原始 result.json 对源恢复明确记 TIS fallback，系统菜单入口等待失败，实际栏仍 ABC，**未冒称实际 IMK 连接已恢复**。用户后续已手动选回，v3与最新恢复见报告060。

用户原未命名及其它窗口保留，自建文档未写入。没有全量包/数据备份、词库覆写、重启、权限增加或诊断文字/剪贴板日志。A 未动。PR #53 保持草稿，不合入/发布；父项循环不关闭与右对齐仍未解决。
