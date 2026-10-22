# 133 候选文字cell零/小尺寸无效几何修复

## 缺陷与复现

132的独立可见窗口在基线/尺寸保护版本都记录AppKit约束常量超限提示。LLDB按提示对精确自有子进程设置_NSLayoutConstraintNumberExceedsLimit断点，并只读打印视图树，看到CandidateLabel内部NSTextFieldSimpleLabel的坐标被钳制为17592186044416；同一调试运行有x/y infinity提示，源日志见132-evidence/constraint-backtrace.txt及constraint-views.txt。LLDB改变了运行环境，不用其时序评估性能。

PaddedCandidateCell.drawingRect对任何bounds直接insetBy(6,2)，在AppKit首次配置文字/布局前的零或过小bounds上可生成null/无效矩形。5363ff8产品代码加新回归：25组宽高（0/1/11/12/64 × 0/1/3/4/26）检测有限、非负、留白在原bounds内，旧版实际失败“padding must remain finite inside small bounds”，见133-evidence/before.txt。

## 最小修复（先写ADR-254）

拒绝非有限/负尺寸bounds并返回零矩形；正常输入的每轴内缩最多为该轴尺寸的一半。正常64×26pt仍精确得到6×2pt留白，点击视图、候选内容/排序/提交及字体均保持。新增回归覆盖25组尺寸、null和正常留白，修复后通过。

## 可见复核与限制

B arm64/macOS27.0.1，三次全新进程，每次60次真实候选更新/显示/隐藏；沿用132实际数据/窗口实验，三个stderr均空，无约束超限或无穷几何提示。源码/空stderr摘要见133-evidence/metadata.json，原始visible-*和驱动visible.py保留。临时窗口已随进程退出，无已装输入法/真实客户端/按键/输入源操作。

本轮证明该复现路径的运行时缺陷已修复，不宣称覆盖所有AppKit提示或已装build2。可见运行仍有一次orderOut最大51.617ms，未关闭原生16ms/30MB，不把消除提示冒充性能达标。133实验只复核警告，不作控制前后性能结论。

完整macOS离线41文件193项、严格双架构及make verify通过；工具链零诊断、200个产物隐私检查通过。下一候选仍0.1.0/build4（与132同一未分发批次），两个独立小提交经同一固定dev→main PR收尾；不追加本轮用户换包/测试，无tag/Release。
