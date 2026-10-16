# 教学生成研究证据（2026-10-16）

对应[报告036](../../reviews/036-generated-wubi-teaching-research.md)。这是只读研究脚本和汇总，不是产品编译器，也不证明全量拆分已经完成。

- `observations.json`：D2/D3/98/新世纪候选表形态统计、112条已核验记录的模板投影结果。
- `source-manifest.json`：固定提交、文件SHA、候选组件/数据的许可边界；不是准入清单。
- `reproduce.py`：不联网，不使用逐字说明列，仅读取现有取码事实生成受限轨迹及短说明；不修改data/或产品产物。

在HANDOFF所列独立工作树运行：

```sh
python3 docs/research/teaching-generation-20261016/reproduce.py \
  --external-dir /private/tmp/lampyris-teaching-research \
  --output-dir /private/tmp/lampyris-teaching-research/reproduced
```

外部输入留在临时研究目录，未打包进仓库。重新准备时先阅读各固定提交的许可；仅研究使用，不自动准入。按source-manifest的固定commit从作者仓库读取相应文件，分别存为`d3-current.txt`、`98-full.txt`、`06-split.txt`，脚本按固定SHA拒绝不匹配。D2使用项目已登记文件；不存在时按项目既有流程获取，禁止用未知镜像替换。

相同输入两次运行的observations和trace-projection输出已逐字节比较一致。trace-projection只有已核验取码单元，没有完整笔画几何或候选拆分竞争过程，不能据此标注教程级全量覆盖。
