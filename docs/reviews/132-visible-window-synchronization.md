# 132 可见候选窗同步成本定位与同尺寸更新保护

## 当前结论

B arm64/macOS27.0.1，main b618972代码，复用真实数据/组件临时拷贝，显示独立非激活窗口，无真实客户端/发键/输入源操作。已装build2保持，工程下一候选0.1.0/build4。环境和源码/数据摘要见132-evidence/metadata.json；调查中负载5.16/4.35/3.35不是每轮起始环境，不能称受控端到端对照。

可见orderOut前三轮P95约16.17/8.73/9.48ms，清空约0.38–0.50ms；与131离屏orderOut约0.018ms差异很大。冷状态条更新1.39–2.03ms，文本/AX设置0.06–0.07ms、尺寸测量1.31–1.94ms，未复现原生status29ms；不为了移动计时边界而提前预热或宣布冷首键已解决。

## 调用栈与最小实现（ADR-253）

对精确自有子进程sample 5秒/1ms：hide分支451个栈样本中381沿SLSConnectionSynchronizeSLSCATransaction→_SLSTransactionWaitSource→mach_msg等待；update→arrange→setContentSize的331个样本中约324在显示器/Space查询的mach_msg等待。样本数不是精确耗时比例，系统私有符号仅诊断使用，产品不调用这些符号。

几何频次实验：60键，构造/布局合计182次setContentSize，其中130次尺寸相同、52次改变。产品仅增加实际contentView.bounds.size与目标尺寸比较；相同时跳过原生setContentSize，仍刷新候选/学习/分页/AX，尺寸变化立即设置。不新增状态缓存、异步隐藏或系统偏好。

临时副本三对可见实验，每变体60次；第二对反序执行，nearest rank：

| 对 | 默认内容更新P95 ms | 保护后P95 ms | 默认hide P95 ms | 保护后hide P95 ms |
|---|---:|---:|---:|---:|
| 1 | 14.041125 | 11.644250 | 25.543125 | 14.483375 |
| 2（反序） | 13.381875 | 10.221333 | 13.705958 | 12.380375 |
| 3 | 12.743250 | 10.866542 | 15.746041 | 11.010208 |

内容更新P95降低约15–24%；**hide最大值三对均变差**（27.638→28.012、17.098→27.356、25.907→31.596ms），不把P95改善冒充长尾问题解决。输入上下文/窗口系统/调度仍须原生确认，16ms/30MB门禁保持。

## 未采纳的动画实验

按[Apple animationBehavior文档](https://developer.apple.com/documentation/appkit/nswindow/animationbehavior-swift.property)，none可关闭orderFront/orderOut自动动画；API说明不证明性能。前三对none较好，但反向第三对hide P95 none20.217ms/default12.432ms，最大39.396ms/default17.343ms，收益不稳定，因此**没有修改动画策略**。保留animation-summary/reversed-summary及全部原始数据。

## 验证与范围

真实AppKit组件定向回归通过：相同尺寸重复更新仍刷新候选、键盘选择与几何；原有尺寸变化、竖排、分页、隐藏旧动作和学习测试继续验证。完整离线41文件193项、strict双架构及make verify通过，工具链零诊断、200产物隐私检查通过。产品修改只有尺寸比较；不修改引擎、词库、配置、已装包和输入源，不追加用户测试。

探针/证据：visible-*、animation-*、reversed-*、resize-*、geometry-0.txt、visible-sample.txt。profile-run的性能值受sample扰动且摘要samples字段沿用60；实际600个HIDE，仅用于调用栈，不纳入成对性能结论。所有采样子进程已退出，自有临时窗口随之关闭；不涉及手工文稿或已装宿主。

## 可见实验暴露的运行时问题

基线与修复副本均产生NSLayoutConstraint常量过大提示，不能称可见运行时零警告。独立进程符号断点+视图树确认：CandidateLabel内部NSTextFieldSimpleLabel被设置为无效/巨大坐标；PaddedCandidateCell对初始零/小bounds直接inset可能生成null矩形。该几何边界另写ADR并补回归后修复；当前尺寸保护不冒充解决它。约束断点会改变执行环境，相关日志不纳入性能统计。
