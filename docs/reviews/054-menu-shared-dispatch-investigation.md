# 054 — 保留菜单层级的统一命令入口对照与报告053纠正

2026-10-17。用户明确不接受额外点击或三模式平铺；本轮不修改产品、不操作现用宿主、输入源、配置或词库。

## 先纠正报告053

报告053只测试了`_buildSelectorDictionaryFromMenuDict:settingCommandID:`，未沿完整创建路径执行后续递归映射。读本机函数实现发现`_createAndInstallMenuSetSelectorDictFromMenuDict:`实际调用`_addActionFrom:toDictionary:forCarbonMenu:base:`。补齐后，Legacy/Modern客户端均给子项分配500/501并对应单独selector。

因此撤回报告053“子项没有命令编号，故系统不能回传”的推断。先前断言只验证了所调用单层助手的行为，不证明系统完整路径。当前父项在递归表中仍无循环selector，自定义view也未序列化；不能把这两点外推为所有子菜单都不支持。

## 新对照与候选修法

独立初始化IMKServer与控制器，使用未显示内存菜单、模拟客户端、数字命令及服务端实际使用的菜单标题元数据，经过IMK服务的`doCommandBySelector_Common:commandDictionary:clientWrapper:controller:`，不再直接绕过服务调用控制器。模拟数据的私有键和运行时接口仅诊断，产品不得依赖。

严格单变量对照：

| 项目 | 独立子项selector | 子项共用现有顶层叶项selector |
| --- | --- | --- |
| 可见层级与条目 | 原父子层级 | 完全相同 |
| 子项命令500/501 | 正常分配 | 正常分配 |
| 服务收到子项命令 | 未进入控制器回调 | 两项均进入控制器，公共kIMKCommandMenuItemName对应正确本地NSMenuItem |
| 顶层对照与关于 | 正常 | 正常 |

两次退出0、stderr为空；子项+顶层同一回调计数从1变3，关于均1，断言通过。说明子项独立selector在服务端可接受动作校验处受阻；将子项共用已经出现在顶层叶项的入口可以穿过这层校验。共用父项selector仍未回调；顶层隐藏中继使菜单同步数组长度不一致并抛异常，均已排除。

候选实现：所有状态命令与三种模式子项使用一个公开ObjC action；在公共IMK命令字典中取选中的NSMenuItem，按稳定tag/命令身份路由到原模式/状态方法。本地AppKit仍接收NSMenuItem。沿用ime-config与既有模式更新，不增加可见菜单项或点击、不添加隐藏中继、不引入私有API产品依赖。

这已证明独立服务接收对照可行，尚非正式包实机修复成功；下一步先ADR、实现最小共享分派回归，再在已授权实机范围验证。父项点击循环及右侧精确对齐仍是独立未决项，不随子项对照通过而关闭；不重新采用ADR-185/186已失败的tab/keyEquivalent方案。

## 证据与限制

目录platforms/macos/build/menu-command-fullpath：

- full-current/standard/flat.txt：完整递归客户端映射。
- shared-leaf-action.m：当前有效独立对照源码。
- comparison-results.json、comparison-current.txt、comparison-shared-leaf-action.txt：单变量服务回传对照。
- create.asm/create-refs2.txt：完整创建函数调用递归助手的本机只读追踪。
- server-current2…5等失败尝试保留：先前模拟客户端缺usesXPC/_clientDOProxy接口，命令数据将NSNumber误写NSMenuItem，随后缺实际标题元数据导致异常；补齐后重新独立对照通过，不冒记前几次成功。

服务实例实际为本机_IMKServerLegacy，Modern/Legacy客户端映射均测试，未声称Modern服务完整接收已测。没有显示/安装Carbon菜单或真实鼠标动作；后续必须验证正式系统入口。

Apple公开[doCommand文档](https://developer.apple.com/documentation/inputmethodkit/imkinputcontroller/docommand(by:command:))及本机SDK头文件规定action接收commandDictionary，其kIMKCommandMenuItemName为选中的NSMenuItem。统一入口利用这一公开消费约定，私有元数据不进实现。
