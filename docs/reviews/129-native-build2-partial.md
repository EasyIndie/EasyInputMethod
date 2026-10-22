# 129 build2原生接管与部分输入核验

## 当前结果

B arm64/macOS27.0.1，固定开发main18fcbbf/0.1.0/build2（公证39728402241），用户手动切源后PID19826，精确路径及执行SHA dc000b6dff48707c18c9ee33052a52260084c795d5856b628eccaaa20cce7cd6匹配。确认新包已实际接管，无需移除/重加/注销。包级身份与备份见128。

复用120逐键CG/自有TextEdit路径、窗口ID及焦点守卫，仅去除本轮未启用的trace增长断言，不自动切源或抢焦点。混输wq→你、nihao→你好、xi'an→西安、shurufa→输入法逐项提交及读回通过，见129-evidence/commits.json。后续huiguiceshi发键后、读回时应用焦点守卫停止（exit1），未取得该项实际文本；不算PASS/产品FAIL，后续模式、选词及最终mixed检查未运行。未重试；本轮自有文稿trap清理无错误，不碰旧手工文稿。

## 性能与数据边界

新宿主在标记准备前已启动，计时默认关闭；本轮没有有效内嵌延迟样本，不冒充性能通过。下次应在ABC安全退出精确宿主后先准备计时，再请求用户一次切开发源，避免切源后才发现启动时未配置。

停止后vmmap读取PID19826：physical30.3M、峰值35.7M；malloc总分配17.1M、碎片6882K、swapped23.7M，不能忽略换出或以RSS关闭30MB门禁。当前样本不是满个人词库/最终RC。单次lsof -nP -a -p19826 -i退出1且无输出，表示该时点无IP sockets，不等于完整生命周期抓包。

生产config/个人词库及开发config SHA保持，开发词库正常学习可变化；mode仍mixed，perf-trace.enabled不存在，当前保留开发输入源，不自动切ABC。见129-evidence/state.json。日志及内存分项保留原始文件。原生16ms/30MB、最终mixed文本及完整同RC发布门禁保持未决。

提交前make verify完整通过、零诊断，200个产物隐私检查通过。已请求用户方便时切ABC以先准备计时；未收到切换前不停止宿主。
