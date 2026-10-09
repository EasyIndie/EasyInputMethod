# 萤火虫项目图标资产

保留 V1–V5 原始图像，供项目文档、应用图标及宣传页面等场景选择。**当前首选 V4（单线标志）**：用户倾向以线条表达简洁。此偏好不删除其他版本；已暂时用于项目 README、macOS 正式应用及独立调试应用的图标。

| 版本 | 原始资产 | 风格 | 建议场景 |
|---|---|---|---|
| V1 | [yinghuo-icon-concept-v1.png](yinghuo-icon-concept-v1.png) | 深蓝微光、青绿双翼 | 项目介绍、品牌展示 |
| V2 | [yinghuo-icon-v2-geometric.png](yinghuo-icon-v2-geometric.png) | 几何造型、光标意象 | 产品标识、图标衍生参考 |
| V3 | [yinghuo-icon-v3-soft.png](yinghuo-icon-v3-soft.png) | 柔和立体、鼠尾草绿底 | 桌面应用图标、展示页面 |
| **V4（首选）** | [yinghuo-icon-v4-line.png](yinghuo-icon-v4-line.png) | 单线轮廓、深底暖光 | 项目主标识、简洁界面 |
| V5 | [yinghuo-icon-v5-paper.png](yinghuo-icon-v5-paper.png) | 浅底纸感、青绿暖黄 | 文档封面、插画展示 |

## 来源与使用

全部由内置 imagegen 按项目需求生成，PNG 原图保持不变。V1 提示词见 [生成记录](yinghuo-icon-concept-v1.md)，V2–V5 见 [备选生成记录](yinghuo-icon-variants.md)。这些文件是栅格设计资产，并非 SVG 矢量源。

衍生资源使用带版本和用途的文件名，保留原图。例如 `yinghuo-icon-v4-app.icns`、`yinghuo-icon-v4-32.png`。正式接入前应检查目标尺寸的可读性；菜单栏单色模板、透明背景和小尺寸版本需专门适配，不直接把完整方形底图作为模板图标。

新增修订继续编号，避免覆盖现有版本。不同场景选用其他版本时，在对应资源或文档中明确版本。

## 当前应用资源

`yinghuo-icon-v4-app.icns` 是 V4 PNG 原图等比缩放生成的 macOS 图标，包含 16–1024 像素规格。两个构建脚本均将其复制为 `Contents/Resources/Yinghuo.icns`，由 CFBundleIconFile 引用。输入法菜单栏的小尺寸模板图标保留现有资源，V4 的单色透明适配另行处理。
