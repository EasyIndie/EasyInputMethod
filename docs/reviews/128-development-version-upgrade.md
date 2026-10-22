# 128 固定开发候选版本与换包闭环修复

## 当前结论

b317590的固定开发签名构建39719374289成功，但静态核验发现其plist缺少CFBundleShortVersionString、CFBundleVersion、LampyrisSemanticVersion。本轮拒绝安装；成功公证不代表版本契约完整。已装仍01fb016，未切源或修改用户配置/词库。

- ZIP SHA-256：`c4ac7b9d1e8b062c2ea1d5b44da91b5d7976b8e0056078d84c63c608973c643d`
- 执行 SHA-256：`393ded55476db0b09db0729331faffd18ce3d991787ce98a48b417bf6d69754b`
- 原因：ADR-249删除模板重复版本后，隔离包直接消费模板的路径未派生版本；生产构建通过macos-build-metadata.py派生，源码路径不同，不将开发包问题推断为生产包失败。

## 最小修复（ADR-251）

隔离/固定开发包复用release_version.identity，从Cargo和受审阅build-number派生完整版本、Apple显示版本及独立构建号。安装器允许新增/改变LampyrisSemanticVersion，身份/服务/开发根、签名/公证及数据保留检查不变。候选版本0.1.0，构建号由1递增2。

## 验证

- 修改前：隔离包回归因缺少CFBundleShortVersionString失败；旧包到有SemVer字段的新包换包回归因声明变化失败。
- 修改后：隔离包6项、固定开发换包9项、隔离CI4项全部通过；临时workspace使用2.3.4-rc.2+fixture/build42，避免仅对当前版本写死。
- 既有拒绝身份变化、当前开发源占用、错误PID、最终校验失败恢复、旧包及数据保留回归继续通过。
- 完整make verify通过、零诊断，隐私检查200个产物；日志/tmp/lampyris-mvp-128-verify.txt。macOS离线全套通过，结构化摘要见128-evidence/offline-summary.json。后续PR/签名包结果以本报告后续记录为准；本地模拟换包不等同真实IMK升级通过。

## 待完成

合入main后重建build2，核验版本/来源/架构/签名/公证、ZIP/执行/数据SHA，再在ABC状态下保留备份换包。集中补原生性能和最终mixed文本；16ms/30MB、升级程序闭环及最终同RC发布门禁仍未关闭。不创建tag/Release。
