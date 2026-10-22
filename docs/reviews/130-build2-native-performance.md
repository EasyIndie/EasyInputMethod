# 130 build2原生性能与部分功能核验

## 当前结论

B arm64/macOS27.0.1，固定开发main18fcbbf/0.1.0/build2，执行dc000b6dff48707c18c9ee33052a52260084c795d5856b628eccaaa20cce7cd6，公证39728402241。用户ABC后精确退出19826，先创建私有计时marker再启动37114；用户切开发源后复用120脚本，逐键源/路径/窗口/焦点守卫，不自动切源。

首轮六词全部实际提交读回：你、你好、西安、输入法、回归测试、人工智能；字节边界截取完整50键，nearest rank total P95 **22.124208ms**、max **58.03925ms**、5键≥16ms；engine P95 **2.439791ms**、max2.647834ms。原生宿主处理指标仍不达16ms，不包括全部IMK调度/屏幕合成，不能由此推断可感知延迟，也不能把历史低值当本候选PASS。

八项附加检查通过：mixed数字第2项/方向第2项均提交像、退格重输你、Esc取消、Enter原码wq、五笔首选你/数字第2项像、拼音nihao提交你好。随后xi'an中途应用焦点守卫停止，未自动抢焦点/重试；剩余拼音与最终mixed未验。附加30条trace独立保留，不混入首轮P95。

## 归因与限制

首键status29.372ms、preedit10.050ms、content8.709ms、caret3.653ms、window4.431ms、engine1.710ms。两次长提交total22.124/31.722ms，已计commit9.162/12.336ms、engine2.440/2.648ms，仍有约10.52/16.74ms未被阶段覆盖。源码确认commit分支在commit计时后调用candidateWindow.hide，其内部orderOut并update空候选（含arrange）；这是下一步验证的具体假设，**尚未独立测量，不宣布根因或优化效果**。不盲目重写引擎，也不放宽门槛。

读取vmmap在采样停止后：physical31.1M、peak37.4M；malloc分配17.1M、碎片7627K、换出19.4M。不能忽略换出或用RSS关闭30MB指标。采样开始未独立记录负载；结束后load3.56/2.87/2.51，仅作环境补充，不是受控前后对照。

## 收尾

失焦后停止发键，自有夹具trap清理无错误；marker已删除，通过现有ime-cli :set→ime-config唯一写路径恢复mode=mixed。缓存计时仍在PID37114中，已请求用户ABC后只停止精确宿主；完成前本轮收尾保持待办。生产数据与开发配置字节SHA保持，开发配置语义恢复，与测试前一致，见state.json。无tag/Release，完整同RC矩阵/升级闭环/独立核验/五日门禁保持未决。

证据：130-evidence/summary.json（实际文本与统计）、trace.jsonl（50完整+30部分）、sample.txt、memory.txt。

提交前make verify完整通过、零诊断，200个产物隐私检查通过。
