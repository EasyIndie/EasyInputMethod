# 124 — TSV排序后直接紧凑构建（ADR-247）

## 改动与证据

main aa01fd0的Table::from_tsv先对输入按码排序分组，再生成紧凑表；紧接finalize把紧凑表完整展开成owned字符串/候选，组内排序后再次打包。改为在现成分组内执行相同weight降序、等权text升序排序，再仅紧凑构建一次。公开finalize、insert、查询和数据格式保持，不改词表/频次/学习顺序。

新增乱序组、等权、负权及重复行混合的确切候选序列回归，检查prefix全局顺序、exact及再次finalize幂等。既有查询oracle/真实表回归保持；本轮ime-table测试通过。

## 离线对照

同一Rust1.98.1、-O/fat LTO/codegen-units=1，同一五笔表SHA；独立进程各解析20次，时间只包住from_tsv，外部time -l采进程峰值RSS。基线/新版交替三对，raw20项、首项及完整系统计数全部保留：[summary.json](124-evidence/summary.json)、[原探针](124-evidence/parse-probe.rs)。每轮P95采用排序索引18（nearest rank）；RSS是进程峰值，包含文件读取和固定公开码查询，并非宿主稳态或排除mmap后的内存。

| 轮次 | 基线解析P95 | 新版解析P95 | 基线峰值RSS | 新版峰值RSS |
|---|---|---|---|---|
| 1 | 21.147ms | 15.938ms | 21.81MiB | 14.97MiB |
| 2 | 10.562ms | 6.921ms | 17.89MiB | 13.45MiB |
| 3 | 21.384ms | 16.942ms | 20.92MiB | 15.69MiB |

三对解析P95下降约21–35%，峰值RSS下降4.4–6.8MiB；轮间波动保留，不挑选最快结果。最初离线预检20次P95=22.175ms/max36.031ms/RSS24084480B单列，不混入三对；首次直接rustc链接未匹配workspace LTO导致链接失败、未生成探针，未取得有效测量，匹配fat LTO后成功。

## 范围与限制

只有首次/重新加载码表的构建成本受益，不加快已经加载的逐键查询；不宣称解决120首键UI状态/窗口67ms长尾，不关闭16ms/30MB门禁。无依赖/网络/unsafe/配置/词库来源变化，未替换已装签名包、未要求用户重测。

19项ime-table回归、workspace完整make verify与严格universal构建均通过、零诊断；隐私扫描200项通过。见124-evidence/tests.txt、universal.txt、verify-summary.txt。后续统一包从合并后的main精确提交构建，不使用功能分支ad-hoc结果作为产品验收。

## 分支清理边界

规范#74已合并aa01fd0，本地main已同步；20远端/21本地历史分支删除被自动审批要求精确批量范围授权而阻止，未删除，清单见123-branch-inventory.json。完整Git bundle已验证，SHA在清单。升级原型暂缓/合入的产品范围问题待用户答复，保留分支；两项等待不阻止本轮离线加载优化，不据此创建多个平行PR。
