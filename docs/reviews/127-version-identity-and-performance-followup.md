# 127：发布版本派生与性能续查

- 日期/环境：2026-10-22，B arm64/macOS27.0.1；固定dev，基线d132c14，工作树改动为ADR-249版本链。不是RC，未安装。
- 当前状态：版本治理实现和本地验证通过；性能门禁、更新安装与App Store准入、同RC A/B及五工作日均未关闭。

## 性能与可靠性（IT-12）

先复用既有探针，无新验收脚本、无真实词库输入。源码确认基础表和个人词库已有共享快照，不重复建设缓存。

本轮早期系统负载1/5/15分钟=72.21/28.11/13.50，不能作为受控优化对照；以下坏值全部保留，不挑最好一轮：

| 既有探针 | 结果 | 边界 |
|---|---|---|
| 空词库五会话渲染2200键 | 冷11.995ms，暖P95 9.035ms/max71.810ms，6键≥16ms；physical27.69MiB | 无IMK客户端，未覆盖生产状态芯片链 |
| 满词库五会话引擎2200键 | P95 8.824ms/max80.729ms；稳态physical21.97MiB；5次学习max0.216ms | 同期渲染探针及系统负载干扰，不比较旧0.95ms；非宿主结果 |
| 满词库五会话渲染2200键 | 冷61.390ms，暖P95 16.479ms/max93.240ms，123键≥16ms；physical31.36MiB/峰42.3M | malloc resident12.7M+swap13.3M，不能忽略swap或从physical简单减mapped file |

沙箱首次渲染因无显示器失败（exit133），未发用户按键；正常桌面权限重跑。系统负载降低后（收尾load1=2.50）顺序复测现有满库五会话：2200键冷20.122ms、暖P95 4.537ms/max16.677ms、2键≥16ms；physical43.55MiB，malloc resident34.5M/swap0、实际分配18.4M/碎片16.0M。完整日志见127-evidence/render-full.txt。说明低physical的早期结果受swap影响，不能当成内存改善；后续需要区分有效分配与分配器高水位，不盲目删除词库或放宽30MB。这不代替已安装签名包原生性能。末项mixed-after-learning仍未补原生文本证据，不计PASS。

## 版本链改动（IT-13）

先记录ADR-249，再实现：Cargo为唯一SemVer源；受审阅packaging/build-number为独立序号；产品plist、独立更新程序、包名、README/SOURCE说明、SBOM、BUILD-INFO和重建路径共用派生结果。模板不再保存重复产品版本。发布校验分别核对tag、产品版本、build、SBOM和归档源码输入，拒绝同显示版本下的构建号错配。

当前实际本地双架构宿主和独立更新程序均为显示0.1.0/build1/完整SemVer0.1.0；构建号增加靠发布候选审阅，当前自动校验只证明候选内部一致，不伪称已证明历史单调。App Store渠道仍待独立验证。

## 验证与范围

- make verify：正常权限全绿、零诊断，隐私扫描200产物；初次沙箱cargo-deny锁缓存只读失败，未当作代码失败或PASS。
- make macos-offline-tests：正常权限41文件193测试全PASS，原始结果127-evidence/offline-summary.json；沙箱回归曾出现控制器/Swift缓存/私有剪贴板三项失败，正常权限对应项均PASS。
- 版本/发布定向20测试PASS（SDK与版本派生5、归档校验15），覆盖2.3.4-rc.2+fixture/独立42，非法SemVer/构建号、产品/SBOM/源码/build错配。
- strict universal宿主构建PASS，check-contract及实际plist回读PASS；初次沙箱Swift缓存拒绝，正常权限重跑成功。
- 默认关闭独立更新程序构建及无参数冒烟PASS；没有feed请求/下载/安装。
- shell语法与git diff --check通过。当前仅本地ad-hoc产物，不作用户包，不创建tag/Release。

下一步先完成本批dev→main唯一PR的CI/合入收尾，再用明确main签名包补原生性能/末项文本；不重复已验收且未受影响的预览场景。更新功能仍保持默认关闭，下载验签/安全替换/恢复尚待，不因版本治理完成而跳过输入门禁。

## 真实归档补验

ca15f49审核归档5,180,663字节，validate-release --review通过；从配对源码离线双架构重建，去签名可执行及三个默认表逐字节一致（日志/两份归档SHA见127-evidence/package.json、package.txt、repro.txt）。这是同机自动重建，不冒充第三方独立核验。实际产物未安装、无正式签名；本批PR #77精确head的CI另行回读。
