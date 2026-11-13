//! 配置 Schema：每个选项的唯一定义。
//!
//! 铁律 R4：默认值 / 取值范围 / 中文说明都只在这里出现一次；
//! 配置文件注释、校验、默认快照、设置界面（ADR-070）均由此派生。

/// 值类型。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ValueType {
    /// 布尔。
    Bool,
    /// 整数，闭区间 `[min, max]`。
    Int { min: i64, max: i64 },
    /// 枚举：只能是 `values` 之一。
    Enum { values: &'static [&'static str] },
    /// 自由字符串。
    String,
    /// 字符串，但只接受空值或 https URL（无凭据、无 fragment）。
    Url,
    /// 逗号/换行分隔的 https URL 列表（按顺序回退；空值=不使用镜像）。
    UrlList,
}

/// 变更后需要即时生效的组件（供设置界面分组与后续 C ABI 使用）。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Scope {
    Engine,
    CandidateWindow,
    Appearance,
    Hotkey,
    Update,
}

/// 单个选项的元数据。
#[derive(Debug, Clone, Copy)]
pub struct OptionSpec {
    /// 点分键名，例如 `"wubi.auto_commit"`。
    pub key: &'static str,
    pub value_type: ValueType,
    /// 枚举显示名（中文），与 `ValueType::Enum::values` **一一对应**；非枚举为空。
    /// 仅供设置界面展示，持久化值仍是 `values` 里的英文标识。
    pub enum_labels_zh: &'static [&'static str],
    /// 默认值的 TOML 字面量（唯一出处）。
    pub default: &'static str,
    /// 设置界面用的短标题。
    pub title_zh: &'static str,
    /// 中文说明，用于生成配置文件注释与设置界面帮助文本。
    pub doc_zh: &'static str,
    pub scope: Scope,
}

/// v1 配置。数组顺序即生成文件时的书写顺序。
pub static SCHEMA: &[OptionSpec] = &[
    OptionSpec {
        key: "mode",
        value_type: ValueType::Enum {
            values: &["mixed", "wubi", "pinyin"],
        },
        enum_labels_zh: &["混输", "五笔", "拼音"],
        default: "\"mixed\"",
        title_zh: "输入模式",
        doc_zh: "五笔优先，想不起编码时用拼音兜底。",
        scope: Scope::Engine,
    },
    OptionSpec {
        key: "wubi.auto_commit",
        value_type: ValueType::Bool,
        enum_labels_zh: &[],
        default: "true",
        title_zh: "四码唯一时自动上屏",
        doc_zh: "打满四码且唯一时直接上屏",
        scope: Scope::Engine,
    },
    OptionSpec {
        key: "wubi.auto_phrase",
        value_type: ValueType::Bool,
        enum_labels_zh: &[],
        default: "false",
        title_zh: "连续单字自动造词",
        doc_zh: "纯五笔模式下连续上屏 2–4 个单字（间隔小于 2 秒、中间没有标点），同样的组合出现 3 次后收进用户词库；默认关闭",
        scope: Scope::Engine,
    },
    OptionSpec {
        key: "wubi.z_key",
        value_type: ValueType::Enum {
            values: &["wildcard", "none"],
        },
        enum_labels_zh: &["万能键", "关闭"],
        default: "\"wildcard\"",
        title_zh: "Z 键行为",
        doc_zh: "万能键可代替想不起的五笔编码；也可关闭",
        scope: Scope::Engine,
    },
    OptionSpec {
        key: "pinyin.fuzzy",
        value_type: ValueType::Bool,
        enum_labels_zh: &[],
        default: "false",
        title_zh: "模糊音",
        doc_zh: "支持 zh/z、ch/c、sh/s、n/l 的基础模糊音",
        scope: Scope::Engine,
    },
    OptionSpec {
        key: "pinyin.scheme",
        value_type: ValueType::Enum {
            values: &["full", "xiaohe"],
        },
        enum_labels_zh: &["全拼", "小鹤双拼"],
        default: "\"full\"",
        title_zh: "拼音方案",
        doc_zh: "全拼，或小鹤双拼（两键一个音节）；双拼只在「拼音」模式下生效，混输模式仍按全拼兜底",
        scope: Scope::Engine,
    },
    OptionSpec {
        key: "dict.extended",
        value_type: ValueType::Bool,
        enum_labels_zh: &[],
        default: "false",
        title_zh: "扩展词库",
        doc_zh: "加载随包提供的扩展码表（约 33.7 万五笔词组、5 万拼音词）；默认关闭。开启后常驻内存约增加 25 MiB，在下一次空闲按键时切换，不打断当前组合",
        scope: Scope::Engine,
    },
    OptionSpec {
        key: "candidate.count",
        value_type: ValueType::Int { min: 3, max: 9 },
        enum_labels_zh: &[],
        default: "7",
        title_zh: "每页候选数",
        doc_zh: "每页候选数（3–9）",
        scope: Scope::CandidateWindow,
    },
    OptionSpec {
        key: "candidate.page_with_comma",
        value_type: ValueType::Bool,
        enum_labels_zh: &[],
        default: "true",
        title_zh: "逗号/句号翻页",
        doc_zh: "组合态下用 , / . 翻页（对齐搜狗/微信）",
        scope: Scope::CandidateWindow,
    },
    OptionSpec {
        key: "candidate.select_with_semicolon",
        value_type: ValueType::Bool,
        enum_labels_zh: &[],
        default: "true",
        title_zh: "分号/引号选第二、三候选",
        doc_zh: "组合态下 ; 选第二候选；纯五笔模式下 ' 选第三候选（混输/拼音下 ' 仍是音节分隔符）",
        scope: Scope::CandidateWindow,
    },
    OptionSpec {
        key: "candidate.pick_char_with_brackets",
        value_type: ValueType::Bool,
        enum_labels_zh: &[],
        default: "true",
        title_zh: "方括号以词定字",
        doc_zh: "组合态下 [ 取首选词的第一个字、] 取最后一个字；首选是单字时仍输出标点",
        scope: Scope::CandidateWindow,
    },
    OptionSpec {
        key: "candidate.show_wubi_learning",
        value_type: ValueType::Bool,
        enum_labels_zh: &[],
        default: "false",
        title_zh: "显示编码与拆字说明",
        doc_zh: "按需显示当前候选的完整五笔码与已核验拆字；不随输入模式自动开关",
        scope: Scope::CandidateWindow,
    },
    OptionSpec {
        key: "candidate.hint_wubi_code",
        value_type: ValueType::Bool,
        enum_labels_zh: &[],
        default: "true",
        title_zh: "拼音上屏后提示五笔码",
        doc_zh: "混输模式下用拼音打出字词后，在光标旁短暂提示它的五笔码，帮助下次直接用五笔",
        scope: Scope::CandidateWindow,
    },
    OptionSpec {
        key: "practice.collect_weak_chars",
        value_type: ValueType::Bool,
        enum_labels_zh: &[],
        default: "false",
        title_zh: "记录薄弱字用于练习",
        doc_zh: "混输模式下把靠拼音打出的单字记到本机 weak-chars.tsv，练习「完整码」时多出这些字；不上传、不影响候选排序，重置练习进度时一并清空",
        scope: Scope::CandidateWindow,
    },
    OptionSpec {
        key: "appearance.theme",
        value_type: ValueType::Enum {
            values: &["auto", "light", "dark"],
        },
        enum_labels_zh: &["跟随系统", "浅色", "深色"],
        default: "\"auto\"",
        title_zh: "外观主题",
        doc_zh: "跟随系统外观，或固定使用浅色、深色主题",
        scope: Scope::Appearance,
    },
    OptionSpec {
        key: "hotkey.toggle_wubi_learning",
        value_type: ValueType::String,
        enum_labels_zh: &[],
        default: "\"alt+l\"",
        title_zh: "显示/隐藏学习区",
        doc_zh: "切换同一学习区显示偏好，不提交当前组合；默认 alt+l（Option 前缀表示「开关」），留空 = 关闭",
        scope: Scope::Hotkey,
    },
    OptionSpec {
        key: "hotkey.toggle_mode",
        value_type: ValueType::String,
        enum_labels_zh: &[],
        default: "\"alt+m\"",
        title_zh: "切换输入模式",
        doc_zh: "循环切换 混合 → 五笔 → 拼音；默认 alt+m（Option = 可选项），留空 = 关闭",
        scope: Scope::Hotkey,
    },
    OptionSpec {
        key: "hotkey.toggle_english",
        value_type: ValueType::String,
        enum_labels_zh: &[],
        default: "\"shift\"",
        title_zh: "中英切换",
        doc_zh: "shift = 单独按 Shift（对齐搜狗/微信） | 组合键如 ctrl+alt+e | none = 关闭",
        scope: Scope::Hotkey,
    },
    OptionSpec {
        key: "hotkey.toggle_width",
        value_type: ValueType::String,
        enum_labels_zh: &[],
        default: "\"alt+f\"",
        title_zh: "全/半角切换",
        doc_zh: "组合键如 alt+f（默认，F = Full-width；⌥Space 与 ChatGPT 等应用冲突） | none = 关闭",
        scope: Scope::Hotkey,
    },
    OptionSpec {
        key: "hotkey.toggle_punctuation",
        value_type: ValueType::String,
        enum_labels_zh: &[],
        default: "\"alt+p\"",
        title_zh: "中英标点切换",
        doc_zh: "组合键如 alt+p（默认，P = 标点；⌥. 会让出 ≥ 符号） | none = 关闭",
        scope: Scope::Hotkey,
    },
    OptionSpec {
        key: "hotkey.toggle_variant",
        value_type: ValueType::String,
        enum_labels_zh: &[],
        default: "\"alt+t\"",
        title_zh: "简/繁切换",
        doc_zh: "组合键如 alt+t（默认，T = 繁体） | none = 关闭",
        scope: Scope::Hotkey,
    },
    OptionSpec {
        key: "hotkey.open_settings",
        value_type: ValueType::String,
        enum_labels_zh: &[],
        default: "\"alt+,\"",
        title_zh: "打开设置",
        doc_zh: "组合键如 alt+,（默认，与其它状态键统一 Option 前缀） | none = 关闭；与菜单项的快捷键提示同源",
        scope: Scope::Hotkey,
    },
    OptionSpec {
        key: "hotkey.open_update",
        value_type: ValueType::String,
        enum_labels_zh: &[],
        default: "\"alt+g\"",
        title_zh: "检查更新",
        doc_zh: "组合键如 alt+g（默认，G = GitHub 更新源） | none = 关闭；与菜单项「检查更新…」的快捷键提示同源",
        scope: Scope::Hotkey,
    },
    OptionSpec {
        key: "hotkey.open_about",
        value_type: ValueType::String,
        enum_labels_zh: &[],
        default: "\"alt+a\"",
        title_zh: "关于",
        doc_zh: "组合键如 alt+a（默认，A = About） | none = 关闭；与菜单项的快捷键提示同源",
        scope: Scope::Hotkey,
    },
    OptionSpec {
        key: "hotkey.open_practice",
        value_type: ValueType::String,
        enum_labels_zh: &[],
        default: "\"alt+k\"",
        title_zh: "练习",
        doc_zh: "组合键如 alt+k（默认，K = 练习） | none = 关闭；打开离线练习窗口",
        scope: Scope::Hotkey,
    },
    OptionSpec {
        key: "input.punctuation",
        value_type: ValueType::Enum {
            values: &["chinese", "english"],
        },
        enum_labels_zh: &["中文", "英文"],
        default: "\"chinese\"",
        title_zh: "标点风格",
        doc_zh: "选择中文或英文标点；快捷键切换会保存此偏好",
        scope: Scope::Engine,
    },
    OptionSpec {
        key: "input.full_width",
        value_type: ValueType::Enum {
            values: &["half", "full"],
        },
        enum_labels_zh: &["半角", "全角"],
        default: "\"half\"",
        title_zh: "字符宽度",
        doc_zh: "选择半角或全角 ASCII；全/半角快捷键切换会保存此偏好（旧版布尔值读取时自动迁移）",
        scope: Scope::Engine,
    },
    OptionSpec {
        key: "input.chinese_variant",
        value_type: ValueType::Enum {
            values: &["simplified", "traditional"],
        },
        enum_labels_zh: &["简体", "繁体"],
        default: "\"simplified\"",
        title_zh: "输出字形",
        doc_zh: "选择简体或繁体输出；快捷键切换会保存此偏好",
        scope: Scope::Engine,
    },
    OptionSpec {
        key: "input.digit_punctuation",
        value_type: ValueType::Bool,
        enum_labels_zh: &[],
        default: "true",
        title_zh: "数字后的 . 和 : 保持半角",
        doc_zh: "数字后紧跟的 . 和 : 不转成中文标点，便于输入小数、版本号与时间（如 3.14、12:30）",
        scope: Scope::Engine,
    },
    OptionSpec {
        key: "input.remember_english_per_app",
        value_type: ValueType::Bool,
        enum_labels_zh: &[],
        default: "true",
        title_zh: "按应用记住中英状态",
        doc_zh: "在某个应用里切到英文后，回到该应用时保持英文；只记在内存里，退出输入法即清空",
        scope: Scope::Engine,
    },
    OptionSpec {
        key: "update.feed_url",
        value_type: ValueType::Url,
        enum_labels_zh: &[],
        default: "\"\"",
        title_zh: "更新来源",
        doc_zh: "留空使用官方 GitHub 发布源；也可填自建 https appcast 地址。只由独立更新程序读取，输入法与核心不联网。",
        scope: Scope::Update,
    },
    OptionSpec {
        key: "update.feed_mirrors",
        value_type: ValueType::UrlList,
        enum_labels_zh: &[],
        default: "\"\"",
        title_zh: "更新镜像",
        doc_zh: "按顺序尝试的备用 appcast 地址（逗号或换行分隔，最多 8 个 https）；默认源不可达时自动回退。只由独立更新程序读取。",
        scope: Scope::Update,
    },
];

/// 按键名查找选项（线性扫描，v1 选项）。
pub fn find(key: &str) -> Option<&'static OptionSpec> {
    SCHEMA.iter().find(|spec| spec.key == key)
}
