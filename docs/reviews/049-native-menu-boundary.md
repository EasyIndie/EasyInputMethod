# 报告049：设备B系统输入菜单实测边界

> 2026-10-17更正：用户指出此前能切换。本文保留当时AX观测，但不能据此推断系统菜单不支持嵌套命令，也不能把其它项目的实现选择当作本项目根因。菜单改版建议暂停；复核与未决项见报告050。

2026-10-17，用户确认B当前空闲，随后明确授权使用原生Swift AX读取并点击精确输入菜单条目；不安装、不新增系统权限、不覆盖现用数据。

## 身份与动作

B已装abdb83f，宿主PID1569，路径~/Library/Input Methods/Lampyris.app/Contents/MacOS/Lampyris；执行文件SHA c4a0703481b56806fd454d0d301874916f82b5685a8a65c0af978ac61b093151。原输入源为Lampyris.default。自建文档build/native-menu-b-519f718e/menu-test.txt，通过完整URL和AX文本区核对，不操作其它文档。

CUA读取TextInputMenuAgent及SystemUIServer超时；经用户明确授权改用Swift AX。权限trusted=true；入口为TextInputMenuAgent PID820的AXExtrasMenuBar/[0]，AXDescription精确为“萤火虫”。根入口AXPress返回-25204，但后续只读观察证明菜单已打开，不能将该返回值直接记为未打开或重试。

系统菜单跟踪期间全局focusedUI不可读，前台仍为已绑定TextEdit；入口AXSelected=true、菜单AXVisibleChildren非空。探针仅在自有文档/宿主/数据摘要/源不变且此精确跟踪态成立时允许下一动作，未删除既有GuardedAXPress的独立账号或焦点门禁。私有探针原始源码、动作、观察日志保留于上述build目录，未作为通用自动化入口发布。

## 实测结果

- 可见标题为“输入模式：混输”，没有传递自定义行的右侧状态布局，原生二级三模式存在。
- 精确父项[0,0,6] AXPress返回0，mode仍mixed，未发生循环。
- 二级“五笔”[0,0,6,0,1] AXPress返回0，菜单随后关闭（AXSelected=false），持久mode仍mixed，配置SHA未变。动作成功返回不等于业务生效。
- 顶层“关于”[0,0,13]作为对照，AXPress后真实“关于萤火虫”窗口打开；由CUA读取真实窗口确认，再关闭本轮打开的窗口。整个命令链并非全面失效，嵌套模式选择未生效。未向签名宿主注入日志，不能仅凭这些观测区分完全未回传与回传后失败。

原生父项带submenu时的系统行为及跨进程自定义view丢失，不能用独立预览的Owner回调/NSMenu.copy/真实控制器直接doCommand通过代替。与[RIMES作者的实现记录](https://github.com/scholay/rimes/blob/main/ARCHITECTURE.md#57-statusmenu--状态-系统输入法菜单单入口)一致：该项目实测系统嵌套维护项可见但未回传，改为顶层命令后在本进程弹出原生菜单。仅作为独立旁证，未复制其实现或引入依赖。协议依据仍是[Apple IMK命令说明](https://developer.apple.com/documentation/inputmethodkit/imkinputcontroller/docommand(by:command:))。

## 数据保持与结果边界

本轮未输入/提交文字，未测试学习区，未修改输入源或启用集合。前后源及完整启用集合相同；config SHA均65643c64fcfd6dd548e20b0c949403e7ff1e440dfe1d4abf9585865e86940c7c，词库SHA均7aa5dc32c4cbb45b96338c5f87f9edcdf7f0e3be8d414ab6aba5df2aae38176d。未创建安装/config/词库全量备份。自建空白文档与本轮关于窗口已关闭；原未命名窗口保留。原始after.json记录保持结果。正式1PASS/22BLOCKED不提升。

## 此前提出的交互备选（暂停，未获采纳）

1. 推荐：保留系统输入源位置，以一个“萤火虫菜单”顶层命令，在selector返回后的下一主队列轮次弹出输入法自身的原生NSMenu。复用现有共享菜单，可实现右对齐、父项循环不关闭及二级选择；代价是多一次点击。不增加第二个状态栏图标或常驻窗口。
2. 保留系统代理：三模式平铺成顶层条目，优先恢复可靠选择；遵循系统点击后关闭行为，放弃原父项循环保持菜单/二级结构要求。

用户要求先查清原因，未采纳上述改版。停止要求二选一，保留原交互目标继续调查。

## 新签名候选只读预检

82794b3的签名公证运行38988089893成功，本机下载至build/rc-ui-82794b3-signed；附件摘要/版本/源码提交/双架构、codesign deep strict、stapler、Gatekeeper均通过，source=Notarized Developer ID；未启动、注册或安装，不能替代上述abdb83f实测。ZIP SHA8ccaba4d1154fd07e8324d6ab7926ff329768f4031185fde1ec1afebaa5f1bca，源码tar SHA bf1d2c704b4eab3c906bf07e8cd5b7dee37c9a429fc84c55018a0cf16affb4c1。本机未再次跨SDK重建；CI同工具链复现通过，独立复现仍待。
