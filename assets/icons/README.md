# 萤火虫项目图标资产

保留 V1–V5 原始图像及无白边修订，供项目文档、应用图标及宣传页面等场景选择。**当前首选 V4 无白边修订（单线标志）**：用户倾向以线条表达简洁。此偏好不删除其他版本；已暂时用于项目 README、macOS 正式应用及独立调试应用的图标。

| 版本 | 原始资产 | 风格 | 建议场景 |
|---|---|---|---|
| V1 | [yinghuo-icon-concept-v1.png](yinghuo-icon-concept-v1.png) | 深蓝微光、青绿双翼 | 项目介绍、品牌展示 |
| V2 | [yinghuo-icon-v2-geometric.png](yinghuo-icon-v2-geometric.png) | 几何造型、光标意象 | 产品标识、图标衍生参考 |
| V3 | [yinghuo-icon-v3-soft.png](yinghuo-icon-v3-soft.png) | 柔和立体、鼠尾草绿底 | 桌面应用图标、展示页面 |
| **V4（首选）** | [yinghuo-icon-v4-line.png](yinghuo-icon-v4-line.png) | 单线轮廓、深底暖光 | 项目主标识、简洁界面 |
| V5 | [yinghuo-icon-v5-paper.png](yinghuo-icon-v5-paper.png) | 浅底纸感、青绿暖黄 | 文档封面、插画展示 |

## 来源与使用

全部由内置 imagegen 按项目需求生成，PNG 原图保持不变；2026-10-09 使用 imagegen 延展内部背景到四边，新增 fullbleed 修订。V1 提示词见 [生成记录](yinghuo-icon-concept-v1.md)，V2–V5 见 [备选生成记录](yinghuo-icon-variants.md)。这些文件是栅格设计资产，并非 SVG 矢量源。

衍生资源使用带版本和用途的文件名，保留原图。例如 `yinghuo-icon-v4-app.icns`、`yinghuo-icon-v4-32.png`。正式接入前应检查目标尺寸的可读性；菜单栏单色模板、透明背景和小尺寸版本需专门适配，不直接把完整方形底图作为模板图标。

新增修订继续编号，避免覆盖现有版本。不同场景选用其他版本时，在对应资源或文档中明确版本。

## 无白边修订（当前可用）

| 版本 | 修订资产 |
|---|---|
| V1 | [无白边](yinghuo-icon-v1-fullbleed.png) |
| V2 | [无白边](yinghuo-icon-v2-fullbleed.png) |
| V3 | [无白边](yinghuo-icon-v3-fullbleed.png) |
| **V4** | [无白边，当前应用/项目标识](yinghuo-icon-v4-fullbleed.png) |
| V5 | [无白边](yinghuo-icon-v5-fullbleed.png) |

修订保留萤火虫主体、姿态、配色和材质，移除外部白框及预制圆角边界，背景延展至方形画布四边。上述原稿为历史参考；新增使用优先选 fullbleed。

## 当前应用资源

`yinghuo-icon-v4-app.icns` 由 V4 fullbleed 生成；正式与独立调试窗口共用。菜单栏采用 [V4 透明单色模板](yinghuo-icon-v4-menu-template.png)，22px/44px衍生为 platforms/macos/Resources/YinghuoTemplate.png 与 @2x 文件，输入源 plist 对应引用。

运行 `./tools/build-macos-icons.sh` 用系统 sips/iconutil 重建 ICNS 与菜单栏资源。原图及修订提示词：保留既有主体和内部背景，去掉外部白框，内部背景延展到四边；菜单版保留V4轮廓，简化为透明底黑色线条，不含发光和底色。

完整历史与备选资产保留于Git仓库。发布源码归档通过 export-ignore 排除非构建所需的历史/备选PNG；保留当前V4 fullbleed、菜单模板、ICNS及生成脚本，第三方仍可离线重建当前应用及图标。归档内指向备选图稿的链接可能不含对应文件。
