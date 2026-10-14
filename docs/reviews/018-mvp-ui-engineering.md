# MVP基础UI改造工程验收

2026-10-14；设备B macOS27.0.1 / 26A434；独立分支codex/mvp-ui-refinement，功能基线66ab513。ADR-165…168；UI01…04代码改造工程完成，产品MVP与最终包实机门禁未关闭。本报告记录工程完成时证据；随后公开流程见HANDOFF/PR #43。未安装或发布Release。

## 完成范围

| 组件 | 改造与验证 |
|---|---|
| 候选 | 输入码/序号/首项17pt加粗无常驻背景，来源留AX；有界非激活翻页、长词换行滚动、错误/既有键位提示保留、隐藏后旧动作不可执行 |
| 设置/菜单 | 原生四pane偏好工具栏、当前页标题、进程内最近pane、15项Schema保持；状态类别明确、既有按键/循环不变；无会话词库操作禁用 |
| 词库/反查 | 显式标签/原生字段/可换行错误，失败保留输入；删除默认取消，导出/导入沿系统文件面板；反查仍只查现有首选拼音 |
| 关于/反馈 | 原生可缩放信息窗口/只读可选择正文/复制及显式链接；成功/失败行内反馈，失败地址可复制；无自动上传或诊断采集 |
| 外观/访问性工程 | 实际亮暗原生控件与窗口chrome、系统语义色、高对比配色分支/边界、无模糊透明内容/新增动画；系统显示通知刷新、pane结束旧编辑、可见AX结果通知 |

设置成功保存清除旧失败提示、失败回读真实值；已由实际生产字段动作验证。候选NSTextField字号与富文本同步，修正旧默认字号导致的基线偏移；可见中文墨迹中心按渲染倍率换算为点，2.5pt为项目光学容差。设置帮助去除内部竞品对齐说明，保留Schema效果/默认值/键位指导。

## 工程证据

- make verify全绿，144 Rust通过、1既有计时忽略；fmt/Clippy/deny零诊断，137产物隐私扫描通过。无新增核心网络/依赖/配置持久化。
- macOS离线：22文件80测试通过，新增4个实际AppKit组件探针；私有配置/词库/剪贴板，没有post事件、显示用户窗口或打开外部链接。布局冲突日志按失败处理。
- strict universal与完整私有预览冒烟通过，Swift诊断零；覆盖真实表单动作保存/失败回读/禁用、FFI分页不提交、AX动作/失效、Schema/主题/热更新、长内容/最小窗口与负坐标/边缘几何。
- 配色26对：正文/帮助/错误/只读/hover及高对比生产策略，普通文字最小7.524:1（目标4.5），高对比必要边界最小3.977:1（目标3）。证据build/mvp-ui04-review/contrast.json，系统高对比标志本轮false。
- 真实离屏控件图：build/mvp-ui01-review、mvp-ui02-review（普通pane含原生toolbar/chrome）、mvp-ui03-review、mvp-ui04-review；私有预览图在build/preview/qa-*。图已检查，标记为离屏原生组件，不冒称活跃客户端截图。

最终日志位于/private/tmp/lampyris-ui-complete-{verify,offline,strict,smoke}.log；本机临时日志不是长期发布证据，正式CI/最终包须独立保存结果。

## 证据边界与后续

macOS27的NSAppearance高对比请求解析为普通Aqua/DarkAqua，已记录实际名称，不能以请求名宣称高对比实机图。高对比策略由同一生产函数显式参数验证；实际系统辅助显示、高对比/减少透明/动态与VoiceOver仍需最终包验收。离线AX动作、焦点资格与几何不能替代真实键盘/客户端焦点、多屏缩放/Spaces或真实IMK性能。

UI05：重新锁完整源码/包身份 → 独立签名公证 → 同一最终包先B后A → 用户独立核验/一人五工作日。A当前不可用；用户已明确批准UI4e660af公开与CI公证，并持续授权本项目同类流程；没有安装/Release安排。旧66ab附件只代表功能基线，不能当完整UI产品包。

完整五笔反查、真实拆字、多字词学习及学习偏好仍为后续NEXT-UI，不把现有键位提示当完整学习区。输入算法、排序、按键、15项Schema、唯一配置与数据来源保持本轮功能基线。

官方依据：2026-10-14核验Apple [Settings](https://developer.apple.com/design/human-interface-guidelines/settings)、[Menus](https://developer.apple.com/design/human-interface-guidelines/menus)、[Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)及官方DocC数据；尺寸/字号/光学容差/配色目标均为项目选择。
