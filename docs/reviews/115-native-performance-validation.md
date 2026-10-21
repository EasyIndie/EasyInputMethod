# 115 — eb151c5 原生性能验收（进行中）

## 当前结论

2026-10-22，B机 arm64/macOS 27.0.1。#66 已按授权合并为 `eb151c5aeb1ff35c4b0188f90bbb5beddce723bb`，公证构建 `39659151625` 已核验安装。用户物理键确认 `wq` 出候选、空格提交“你”；之后独立TextEdit夹具三轮共18次词提交断言通过，取得150个按键样本。

受控暖态样本 total P95 **11.606ms**，max **18.464ms**，2次≥16ms；引擎P95 **1.122ms**。采样前非受控手工阶段另有4条计时，最大 **74.170ms**，完整保留，未混入暖态分位数。**不能宣布产品<16ms全面达标**，也不能把新旧非同条件样本当作性能改善幅度。

## 产物与安装证据

完整机器证据见 [package.json](115-evidence/package.json)。ZIP SHA-256：`9200cffb7cd2821e95b475487a91b96a94d032ccd3b6cdb2fc5a5a06359bec1b`；执行 SHA-256：`67028d52a2106489176d4d40cf81d3fcb6ad5e3d0bd8598b347b268d553fd3a5`。

签名、公证、stapler及打包两张核心表核验通过。用户切 ABC 后换包，启用输入源集合未变；安装前后生产和开发的配置、个人词库四份 SHA 全部一致。旧包保留在固定私有根 `replacement-xuw9_efr/previous.app`。未包含更新原型。

## 首次采样过程（历史）

仅固定开发私有根开启测试计时；日志仅含 engineUs、totalUs、candidates、committed，不记录输入内容。trace 位于本机 `platforms/macos/build/acceptance-115/trace.jsonl`。用户确认切回开发源后只读回报匹配；PID3115的加载路径与执行SHA匹配新包。首组逐键守卫未报失焦，但 `wq` + 空格实际文稿为“w”，预期“你”；trace仍为0字节，因此立即停止，未进行后续轮次。自有临时文稿经exit trap关闭，用户文稿保持。详见 [sampling-attempt.json](115-evidence/sampling-attempt.json)。该次不计性能样本，未确认产品归因；后续物理键与受控补采结果见下节。

补采使用唯一自有 TextEdit 临时文稿逐键校验应用、文档路径、窗口、输入焦点后输入公开样例；失焦立即停止。统计绑定采样起止偏移，采样前其他输入另存。totalUs 从 session.feed 前开始，到预编辑与候选更新返回为止，不包含此前事件分类、IMK调度及屏幕合成；不能当作完整端到端延迟。

本轮 marker 已移除；运行中宿主缓存计时路径，用户切 ABC 后按精确路径/SHA/PID守卫停止宿主，已确认退出；后续启动不再采样。不关闭用户保留文稿1902、2221、2372。

## 发布边界

本轮不关闭 IT-12、MVP或同RC门禁。A/B、应用兼容、正式安装升级恢复、独立重建及五工作日试用仍待；升级原型 #64 继续暂缓，不创建 tag 或 Release。


## 本候选原生验证结果

- 用户确认：保留的“萤火虫性能验收-115.txt”手工 `wq` 出候选，空格提交“你”。这是本候选物理键证据。
- 首次自动夹具失败的事实保留。物理键对照后，新自有夹具增加逐键trace增长检查，三轮 `wq / nihao / xi'an / shurufa / huiguiceshi / rengongzhineng` 分别提交 `你 / 你好 / 西安 / 输入法 / 回归测试 / 人工智能`，18项一致。每键路径/窗口/AX输入焦点守卫；自有夹具已关闭，保留手工窗口。
- [summary.json](115-evidence/summary.json)绑定trace字节偏移280…10615、SHA与nearest-rank分位数；[trace.jsonl](115-evidence/trace.jsonl)仅包含这150条，132条候选更新、18条提交。候选更新P95 11.826ms；提交P95 11.008ms。不得把阶段分位数相加。
- [precohort-trace.jsonl](115-evidence/precohort-trace.jsonl)保留采样前4条非受控记录，其中total最大74.170ms、engine最大64.044ms。它们不满足同一受控输入序列，不能推断冷启动分位数；也不能因后续暖态较快忽略首次/学习提交长尾，仍需独立定位。
- RSS起始44,416KiB，三轮末53,264 / 52,592 / 52,208KiB。RSS不等于“不含mmap常驻内存”，本轮没有该分项，不能用RSS直接关闭或判定30MB门禁。
- 测试marker已精确删除；用户切ABC后源/路径/SHA守卫通过，仅SIGTERM开发宿主PID3115并确认退出，源集合与ABC保持。计时已完全关闭，[cleanup.json](115-evidence/cleanup.json)。生产两SHA和开发config保持；开发私有词库因正常选词学习变化，未清空/还原。

## 下一步最小行动

计时收尾已完成。独立定位首次/学习提交长尾与候选更新>16ms样本，必要时按ADR先补宿主分段计时。保持16ms/30MB口径不变，再扩大到三模式、目标应用和A机。版本/升级及正式RC顺序保持ADR-240，不因这一小组暖态结果提前关闭输入体验出口。
