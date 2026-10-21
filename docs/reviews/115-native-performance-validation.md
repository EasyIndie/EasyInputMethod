# 115 — eb151c5 原生性能验收（进行中）

## 当前结论

2026-10-22，B机 arm64/macOS 27.0.1。#66 已按授权合并为 `eb151c5aeb1ff35c4b0188f90bbb5beddce723bb`，公证构建 `39659151625` 已核验并安装到固定开发身份。原生输入与性能尚待采样，不能宣布 <16ms 达标，也不继承旧候选的手工通过结果。

## 产物与安装证据

完整机器证据见 [package.json](115-evidence/package.json)。ZIP SHA-256：`9200cffb7cd2821e95b475487a91b96a94d032ccd3b6cdb2fc5a5a06359bec1b`；执行 SHA-256：`67028d52a2106489176d4d40cf81d3fcb6ad5e3d0bd8598b347b268d553fd3a5`。

签名、公证、stapler及打包两张核心表核验通过。用户切 ABC 后换包，启用输入源集合未变；安装前后生产和开发的配置、个人词库四份 SHA 全部一致。旧包保留在固定私有根 `replacement-xuw9_efr/previous.app`。未包含更新原型。

## 采样范围与收尾

仅固定开发私有根开启测试计时；日志仅含 engineUs、totalUs、candidates、committed，不记录输入内容。trace 位于本机 `platforms/macos/build/acceptance-115/trace.jsonl`。用户确认切回开发源后只读回报匹配；PID3115的加载路径与执行SHA匹配新包。首组逐键守卫未报失焦，但 `wq` + 空格实际文稿为“w”，预期“你”；trace仍为0字节，因此立即停止，未进行后续轮次。自有临时文稿经exit trap关闭，用户文稿保持。详见 [sampling-attempt.json](115-evidence/sampling-attempt.json)。等待物理键对照，不将此直接归因产品缺陷，也不计作性能样本。

计划在唯一自有 TextEdit 临时文稿逐键校验应用、文档路径、窗口、输入焦点后输入公开样例；失焦立即停止。统计应绑定采样起止偏移，排除采样前其他输入。totalUs 从 session.feed 前开始，到预编辑与候选更新返回为止，不包含此前事件分类、IMK调度及屏幕合成；不能当作完整端到端延迟。

采样后移除本轮 marker；运行中宿主缓存计时路径，需用户切 ABC 后按精确执行路径停止开发宿主，确认后续启动不再采样。不关闭用户保留文稿1902、2221、2372。

## 发布边界

本轮不关闭 IT-12、MVP或同RC门禁。A/B、应用兼容、正式安装升级恢复、独立重建及五工作日试用仍待；升级原型 #64 继续暂缓，不创建 tag 或 Release。
