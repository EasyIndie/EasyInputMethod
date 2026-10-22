# 126 — 固定dev与升级原型收拢（ADR-248）

## 分支与归并范围

用户明确要求统一一个迭代分支，并授权升级原型经评审/必要补验进入main。将已合并工作分支重命名为固定dev；main仅保留受保护合入/签名构建职责。所有后续工作顺序在dev进行，不再按任务开feature/fix/docs分支。用户精确授权的20远端/21本地历史分支已逐项SHA核验后原子清理，完整bundle可恢复，清单见123；原型恢复分支只读保留至独有改动进入main。

从关闭#64@eab23b1恢复独立Updater目录、ADR-239与历史110证据，不恢复过期HANDOFF/ROADMAP。上游8d1d4b8源码/Apache-2.0许可/镜像测试的SHA已重新从GitHub固定提交核验一致（126-evidence/upstream-verified.json）。构建采用本地Swift target，无Sparkle二进制或远程Swift包依赖；完整原许可与来源元数据保留，Rust依赖闭包不变。

## 评审发现及必要修改

当前严格并发编译真实失败：从主actor向异步check传递configuration缺Sendable类型契约。为两个仅含不可变String/URL/Data值的public配置/结果结构添加编译器检查的Sendable，无@unchecked。PROVENANCE分别记录上游及本地SHA；verify-vendor反向移除恰好两行补丁后校验上游源码完整一致，避免静默改vendored实现。原始失败日志保留strict-before.txt，不能把诊断误称已证明运行时竞态。

补Sendable编译约束回归、XML深度/1000条上限/重复enclosure、非法签名长度/零长度/畸形版本离线回归；既有数字版本排序、恶意DTD/实体、配置/渠道与跨源重定向回归保持。构建显示版本由Cargo workspace.package.version派生，去掉新引入的0.1.0硬编码；默认构建号1仅未发行原型占位，不能算ADR-240全局构建号已实现。tests/build均开启warnings-as-errors及strict-concurrency=complete，并加入CI。

## 已验证与能力边界

离线8项XCTest、默认关闭release构建、来源/许可/补丁摘要通过；无参返回关闭提示，缺正式配置--check以2退出并提示未发送请求，元数据无feed/公钥，otool无Sparkle依赖（126-evidence/smoke.json）。未请求example.test或真实feed；这不是线上更新或下载包认证测试。

无UserDefaults/注册表/第二用户配置/后台运行/遥测/输入数据访问；渠道/feed/公钥仅独立签名构建元数据，未来用户偏好仍只能走ime-config。源代码中check只在显式--check且配置校验成功后调用；仅临时无cache/cookie/credential会话，可见IP等正常连接信息，不能称独立程序零网络。Rust核心/IMK不链接它，默认输入法包不携带它。

返回metadata不可信，公钥/签名长度检查不等于Ed25519验签。没有下载、目标系统/架构筛选、payload签名验证、安装/退出宿主/备份回滚、GUI、后台偏好或App Store集成；这些仍为后续工程，不因原型入main宣称升级完成。正式feed/公钥未提供，默认保持关闭。

本轮make verify完整通过、零诊断，原Rust依赖/200产物网络符号断言通过；独立Updater的8项离线XCTest与严格并发release构建通过，验证摘要随后随本批提交；独立程序的联网许可不放宽Rust原有零网络门禁。签名开发包125已静态核验但未安装，已装输入法未动，不要求用户重复全套测试。
