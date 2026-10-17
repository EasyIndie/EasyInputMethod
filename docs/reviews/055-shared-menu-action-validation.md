# 055 — 统一菜单命令入口实现与验证

2026-10-17；ADR-202；RC-UI-01。用户要求验证报告054方案，原系统菜单层级与可见数量保持，不增加点击、不增加隐藏中继。

## 实现

父项、四状态和三模式子项统一为performInputMenuCommand:，稳定NSMenuItem.tag区别八种命令。本地AppKit读取sender菜单项；IMK读取公共kIMKCommandMenuItemName中的菜单项。禁用项、未知tag、错误action与畸形sender不执行。正式控制器和私有预览共用解析，仍调用既有ime-config模式写入与会话更新，不增加配置、依赖、网络或第二份状态。

测试专用IMKMenuServiceProbe经过服务端接受动作校验，再将系统解析后的NSMenuItem交给正式控制器。私有方法及模拟客户端仅链接到未注册测试app；生产二进制检查未包含该探针、IMKMenuTitle或私有服务选择器。

## 验证结果

| 验证 | 结果 |
| --- | --- |
| 修改前新增服务回归 | 按预期失败：service boundary delivers cold submenu choice；原日志另有系统sandbox_extension信息，完整记录保留 |
| 修改后服务回归 | 1项通过：冷控制器、三模式、四状态双向、不串改mode、停用重激活同步 |
| 共享菜单组件 | 1项通过：原层级/数量、无隐藏中继、错误参数/禁用保护、父项本地循环、子项及唯一选中 |
| 私有真实FFI预览 | 1项通过：配置订阅、快捷键、四状态、写入锁失败与恢复、无学习；现用config/词库摘要前后相同 |
| 服务回归生产-O/-whole-module-optimization | 确认执行1项并通过 |
| 生产arm64/x86_64，macOS13部署目标 | 两架构均编译成功，标准输出/错误为空 |
| make verify | fmt/clippy/test/deny/零网络全绿，176产物，无编译诊断 |

证据：platforms/macos/build/menu-command-fullpath/{regression-before,regression-after,regression-complete,component-tests,preview-tests,optimized-regression,make-verify}.txt；双架构结果platforms/macos/build/shared-menu-validation/build-results.json。证据均保留，未运行旧包升级脚本或修改已装正式宿主。

## 未决及实机准备

通过范围是隔离服务接收与产品处理逻辑，不等于系统菜单实机通过。B仍为已装a5d456b正式包；父项在系统菜单点击循环/保持打开、右侧精确对齐均保持待验，不在本次通过声明中。

后续实机结果见报告056：用户授权后首个五笔子项仍mixed，FAIL并停止，另外两模式未执行；已恢复原正式包及原mode/源，数据字节不变。原计划为二级选择三种模式并核对菜单/配置/会话。新的候选不是此前已获临时替换许可的current/standard-parent两份诊断包，须在具体候选可核验后确认新替换范围；不能把“验证方案”扩大为自动正式升级或合入发布。无须用户重启、无全量数据备份、不覆盖现用词库。

候选已准备：提交f1eea345026a68d1a2124019fb017501545cae3c；草稿[PR #53](https://github.com/EasyIndie/EasyInputMethod/pull/53)，未合入。build/shared-menu-validation/Lampyris.app为双架构本地adhoc签名候选、未公证，codesign --verify --deep --strict通过；执行SHA b0c623282a776595e43c46a9f7e029d02bb6df04022027ee0178e22fd37da1a1，未安装。manifest在同目录candidate-manifest.json。用户已明确同意本轮临时替换与B空闲；执行失败并按约恢复，见报告056。
