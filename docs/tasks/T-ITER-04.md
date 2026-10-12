# T-ITER-04：快捷键统一解析与语义校验

- 状态：已完成（ADR-093；配置、typed FFI与两宿主适配已接入）
- 模型建议：pro（涉及资源所有权、状态契约或跨层行为判断）
- 前置：无
- 目标：配置、菜单和执行对同一快捷键有相同解释（P1，对应迭代计划 IT-04）
- 步骤：先 ADR 明确修饰键别名、大小写、禁用值、重复冲突及无修饰键边界；读取 add-config-option Skill；在 ime-config 建立唯一语义校验，运行时与菜单复用规范；旧配置无效值给清楚错误及恢复路径。
- 验收：banana 不可保存；重复 ctrl+space 不可静默生效；control/ctrl、option/alt、command/cmd 的约定一致；大小写/禁用/默认键回归，面板菜单与执行一致。 提交前 `make verify` 零诊断；涉及 Swift 跑 strict 宿主构建与隔离预览；脚本先在隔离用户环境覆盖成功/失败/中断，不先用真实数据试错。
- 铁律提醒：配置只走 ime-config；行为/协议变更先 ADR；核心零网络；一次一个改动，文档同步。
- 禁止：各宿主自建第二套配置语法；自动猜测冲突键；未经 ADR 改默认键。
- 参考：[迭代计划](../迭代计划.md)、[审计009](../reviews/009-macos-product-engineering-audit.md)、根目录 AGENTS.md；配置行为另读配置架构.md与相关ADR。

## 验证结果

配置14项单测通过，其中新增非法语法/冲突不写盘、别名规范、坏重载保留快照及恢复用例；隔离预览验证typed ABI、非法/冲突拒绝与禁用。make verify零诊断、strict arm64宿主构建及预览冒烟通过。菜单与运行时共用ConfiguredHotkey，配置语法只在ime-config解析。未替换已安装包，最终候选实机回归仍由IT-14负责。
