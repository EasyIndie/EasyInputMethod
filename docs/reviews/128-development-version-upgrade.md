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

## 当前合入与装包结果

PR #78最终head fc65b65四CI全部SUCCESS（CI39721994430，DCO39721994432），merge合入main `18fcbbfdc64147eed557b1783d665e1314198f69`，固定dev快进同步，无开放PR。此前ADR-250流程规范一并合入。

同源生产审核包39719076526（b317590/build1）静态核验三项版本完整；ZIP SHA `a8668e1d89e871504a9b2c6a91d6cdc7ff1b8a0dff2692f3bef5e3efbfa7f39d`，未安装。它不等同开发包，也不能继承其原生验收。

main18fcbbf固定开发公证构建39728402241成功，版本0.1.0/build2、源码及架构绑定、Developer ID/项目Team、Gatekeeper、stapler通过，安装器已在ABC状态下原位换包。ZIP/执行SHA见[package.json](128-evidence/package.json)，四份配置词库SHA保持，启用源集合与ABC保持，旧包在replacement-yu8hn1jy/previous.app，完整结果见[installation.json](128-evidence/installation.json)。未自动切源；此时只完成包级升级，实际新宿主输入尚待用户切开发源。

## 满库长程内存补充（非原生IMK）

18fcbbf工作树，B arm64/macOS27.0.1，开始load averages3.27/3.38/3.20；复用run-render-perf.sh --max-user-dictionary --stress，合成10000条/1978920字节个人词库、五会话、1000轮/22000键。第100…1000轮phys_footprint在29.58…30.11MiB波动，结束29.89MiB；未见随轮数持续增长，但没有swap/分配分类同期取证，不能用此替代127高水位或关闭30MB门禁。冷键11.870ms、暖P95 6.410ms、最大18.153ms、1键≥16ms；无IMK客户端/状态完整链路，不关闭原生16ms。探针末次lsof未见IP socket，不等同覆盖全部宿主生命周期。原始输出见[render-stress.txt](128-evidence/render-stress.txt)。
