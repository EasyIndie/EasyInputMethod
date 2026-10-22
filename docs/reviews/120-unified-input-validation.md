# 120 — 统一输入修复包验收（原生采样及收尾完成）

## 当前状态

#70词库同步失败重试与#71同尺寸布局复用均四CI绿后合并，main `01fb0164d1b52cc22e4a34a69054a71abbd45631`。固定开发arm64公证39671498990成功并已安装，执行SHA `ff2e92239911d82bdc1201ac23c81300cad3edd74d627ca0ed63deaf1196a85b`；ZIP SHA `2408a6bdd52026a08fab7eeda386f76f037b6e7c97995250cb35460d8704b583`。

签名、公证、stapler、源码及打包两表SHA核验通过；换包前后ABC/源集合与生产/开发配置词库四SHA保持。旧a3853aa保留在固定根replacement-2gqm5ixs/previous.app。完整证据见[package.json](120-evidence/package.json)。

用户授权开始后，PID51595/执行SHA及开发源回读匹配，在唯一TextEdit夹具逐键守卫采样。首轮6词50键全部正确：你、你好、西安、输入法、回归测试、人工智能。数字第二项、横向右键第二项、退格、Esc、回车原码提交、五笔首项/第二项、拼音全拼/显式分隔三词检查通过。

最后切回混输的复查触发“本键无trace”守卫（exit97），立即停止，未重试；最终文字未读取，不能将该项判PASS，也不能仅据缺trace判输入法故障。配置语义已回读恢复初始mixed。自有夹具已清理，用户窗口保留。功能检查期间读取vmmap，不能排除其对该部分执行时序的影响；首轮性能样本在vmmap之前完整结束。

50键按nearest rank：engine P95 **1.084ms**/max1.940ms；total P95 **10.478ms**/max**67.125ms**，1键≥16ms。首键status28.518ms、preedit12.472ms、content10.646ms、window11.618ms，engine0.735ms；首次宿主布局仍需定位。窗口阶段P95=0.741ms，历史117为3.110ms，但单轮/首次状态不同，不作为受控因果对照或全场景达标。原始记录、字节边界、SHA及实际提交见[summary.json](120-evidence/summary.json)、[trace.jsonl](120-evidence/trace.jsonl)、[sample.txt](120-evidence/sample.txt)。

输入态vmmap physical31.2M/peak41.1M，明显高于ABC空闲8433K；尚不等价排除mmap后的常驻指标，30MB门禁保持。见[loaded-vmmap.txt](120-evidence/loaded-vmmap.txt)。本包没有用户文字采集，trace仅固定数值。

用户切ABC后核对精确路径/执行SHA，仅停止PID51595并确认退出；marker不存在，缓存计时已关闭。生产两SHA/开发配置保持，私有词库正常学习变化，见[cleanup.json](120-evidence/cleanup.json)。本次窗口回读仅2372仍在，1902/2221不在列表；本次未执行关闭手工文稿。
## 独立历史未决项复核

cf48a9e工作树上正常权限复跑test-tools-presentation.py通过（12.825s），验证命名私有剪贴板复制返回/读取一致及提示。旧失败保留历史，不再列为当前可复现阻断；未变更复制代码，未归因旧失败原因，也不宣称本机完整离线套件全绿。原始日志/范围见120-evidence/tools-presentation-recheck.*，不作为新包原生PASS。

## 收尾与边界

本轮已完成精确marker删除、ABC确认、精确宿主停止与数据SHA核验；运行进程缓存路径，单删marker不足以完全关闭计时。所有真实数据保留，仅私有正常学习变化。

16ms/30MB、同RC应用/A-B/正式安装升级恢复/独立重建与五日仍未关闭。版本升级暂不扩大，不创建tag或Release。


## 额度恢复后的只读核对

主线仍为01fb016，固定开发包执行SHA匹配。恢复时当前源ABC，宿主PID51595，trace0条，尚未进入本包自动验收；未重新换包、未自动切源或发键。精确匹配保留窗口2372的名称/路径后已展示，未修改文字。

vmmap -summary读取该精确宿主成功：空闲物理占用8433K、峰值8865K；此时未接管输入，不能用于关闭加载词库/输入态或满库的30MB指标。原始分类与身份范围见120-evidence/idle-vmmap.txt、idle-memory.json。
