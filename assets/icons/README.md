# 萤火虫项目图标资产

保留 V1–V5 原始图像及无白边修订，供项目文档、应用图标及宣传页面等场景选择。**当前官方标识为菜单V5飞行萤火虫轮廓**，应用/项目采用官方配色衍生，见本文末。历史V4及其他版本全部保留。

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
| **V4** | [无白边，历史应用标识](yinghuo-icon-v4-fullbleed.png) |
| V5 | [无白边](yinghuo-icon-v5-fullbleed.png) |

修订保留萤火虫主体、姿态、配色和材质，移除外部白框及预制圆角边界，背景延展至方形画布四边。上述原稿为历史参考；新增使用优先选 fullbleed。

## 当前应用资源

`yinghuo-official-app.icns` 由官方飞行萤火虫母版生成；正式与独立调试窗口共用，原V4 ICNS保留为历史资产。菜单栏采用 [菜单V5飞行萤火虫模板](menu-v5/yinghuo-menu-v5-master.png)，18pt/36px Retina衍生为 platforms/macos/Resources/LampyrisTemplate.png 与 @2x 文件，输入源 plist 对应引用并声明 `TISIconIsTemplate=true`，由系统适配亮暗菜单栏与选中状态。

运行 `./tools/build-macos-icons.sh` 用系统 sips/iconutil 重建 ICNS 与菜单栏资源。原图及修订提示词：保留既有主体和内部背景，去掉外部白框，内部背景延展到四边；菜单版保留V4轮廓，简化为透明底黑色线条，不含发光和底色。

完整历史与备选资产保留于Git仓库。发布源码归档通过 export-ignore 排除非构建所需的历史/备选PNG；保留官方应用母版、菜单V5母版、官方ICNS及生成脚本，第三方仍可离线重建当前应用及图标。归档内指向备选图稿的链接可能不含对应文件。

## 菜单栏精修 V2（设计候选）

2026-10-09用户确认输入及翻页正常，要求强化菜单图案记忆点。新增 `menu-v2/`，独立保存原模板，暂未替换正式资源或已安装公证包。

- [透明母版](menu-v2/yinghuo-menu-v2-master.png)：圆弧触角、舒展双翼、水滴形腹部及留白光带，两道短光芒强调萤火虫身份；单色圆端线条，沿用V4简洁风格。
- [亮暗及实际尺寸预览](menu-v2/preview-light-dark.png)：上方放大轮廓，下方18pt小图；预览为本地绘制，不代表已验收系统菜单效果。
- `menu-v2/YinghuoTemplate.png`（18×18）与 `YinghuoTemplate@2x.png`（36×36），供后续接入现有TIS模板着色机制。

来源：内置imagegen，以现有V4菜单模板为参考；真透明背景。设计提示强调1.2pt级圆端线条、80%主体占比、单色尾部留白光带，避免颜色/阴影/背景及过密细节。预览通过AppKit在亮暗背景渲染同一alpha轮廓。

## 菜单图标比选 V2–V5

[统一亮暗对比](menu-comparison-v2-v5.png)：上排浅色、下排深色；每格含放大轮廓及18pt实际尺寸。V2为既有精修，V3舒展叶形双翼与独立光点、V4收翼实心轮廓、V5斜向飞行与尾端星光。每版母版与18/36px资源单独保存到 `menu-v3/`、`menu-v4/`、`menu-v5/`；由imagegen分别生成。菜单编号独立于应用图标V1–V5。用户已选择菜单V5并接入构建资源，其他版本为备选；已安装公证包尚未更新。亮暗图是同一alpha轮廓黑白着色的AppKit预览，不代表系统实际显示验收。

## 官方统一标识（2026-10-09）

用户指定当前菜单V5飞行轮廓为官方标识。[官方应用母版](yinghuo-official-icon.png)采用相同姿态的深松石绿底、浅玉白主体、柔蜂蜜金尾部；[macOS导出母版](yinghuo-official-macos.png)保留圆角外围透明，[官方ICNS](yinghuo-official-app.icns)由该导出母版经生成脚本衍生，项目README/正式应用/独立预览均已接入。菜单使用menu-v5单色透明母版与系统模板着色，保持同一品牌轮廓。此前应用V4与所有备选均保留为历史资产。

应用母版由imagegen以菜单V5为唯一几何参考生成；菜单亮暗模式不改变姿态，仅由系统适配前景着色。已安装包的菜单资源与仓库一致、TISIconIsTemplate=true；用户反馈暗黑模式样式不变，颜色对比是否异常尚待明确，不判定着色验收通过。

## 官方配色规范

设计目标色：深松石绿 `#163C38`、浅玉白 `#E5EEE4`、蜂蜜金 `#EBC46B`；背景仅有克制的深浅变化。主体及尾部对背景的目标色对比分别约10.18:1/7.27:1，是图形辨识预检，不作为文字WCAG验收。生成PNG为栅格配色近似，以上为品牌目标色。

遵循 [Apple App icons指引](https://developer.apple.com/design/human-interface-guidelines/app-icons/) 的简单背景、清晰主体、满铺不透明底层与一致品牌特征；官方母版1024×1024。传统macOS ICNS使用单独的透明外围圆角导出图，外圈不是白边。当前没有Icon Composer分层文件，不把兼容ICNS宣称为新版全部外观资源交付。历史深蓝母版独立保留。
