//! 配置 Schema：每个选项的唯一定义。
//!
//! 铁律 R4：默认值 / 取值范围 / 中文说明都只在这里出现一次；
//! 配置文件注释、校验、默认快照、设置界面（未来）均由此派生。

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
}

/// 变更后需要即时生效的组件（供设置界面分组与后续 C ABI 使用）。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Scope {
    Engine,
    CandidateWindow,
    Appearance,
    Hotkey,
}

/// 单个选项的元数据。
#[derive(Debug, Clone, Copy)]
pub struct OptionSpec {
    /// 点分键名，例如 `"wubi.auto_commit"`。
    pub key: &'static str,
    pub value_type: ValueType,
    /// 默认值的 TOML 字面量（唯一出处）。
    pub default: &'static str,
    /// 中文说明，用于生成配置文件注释。
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
        default: "\"mixed\"",
        doc_zh: "mixed = 五笔优先 + 拼音兜底（推荐） | wubi = 仅五笔 | pinyin = 仅拼音",
        scope: Scope::Engine,
    },
    OptionSpec {
        key: "wubi.auto_commit",
        value_type: ValueType::Bool,
        default: "true",
        doc_zh: "打满四码且唯一时直接上屏",
        scope: Scope::Engine,
    },
    OptionSpec {
        key: "wubi.z_key",
        value_type: ValueType::Enum {
            values: &["wildcard", "none"],
        },
        default: "\"wildcard\"",
        doc_zh: "z 键：wildcard = 万能键 | none = 关闭",
        scope: Scope::Engine,
    },
    OptionSpec {
        key: "pinyin.fuzzy",
        value_type: ValueType::Bool,
        default: "false",
        doc_zh: "模糊音（zh=z、ch=c、sh=s、n=l…）",
        scope: Scope::Engine,
    },
    OptionSpec {
        key: "candidate.count",
        value_type: ValueType::Int { min: 3, max: 9 },
        default: "7",
        doc_zh: "每页候选数（3–9）",
        scope: Scope::CandidateWindow,
    },
    OptionSpec {
        key: "candidate.page_with_comma",
        value_type: ValueType::Bool,
        default: "true",
        doc_zh: "组合态下用 , / . 翻页（对齐搜狗/微信）",
        scope: Scope::CandidateWindow,
    },
    OptionSpec {
        key: "appearance.theme",
        value_type: ValueType::Enum {
            values: &["auto", "light", "dark"],
        },
        default: "\"auto\"",
        doc_zh: "auto = 跟随系统 | light | dark",
        scope: Scope::Appearance,
    },
    OptionSpec {
        key: "hotkey.toggle_mode",
        value_type: ValueType::String,
        default: "\"ctrl+shift+m\"",
        doc_zh: "循环切换 混合 → 五笔 → 拼音",
        scope: Scope::Hotkey,
    },
    OptionSpec {
        key: "hotkey.toggle_english",
        value_type: ValueType::String,
        default: "\"shift\"",
        doc_zh: "中英切换：shift = 单独按 Shift（对齐搜狗/微信） | 组合键如 ctrl+shift+space | none = 关闭",
        scope: Scope::Hotkey,
    },
    OptionSpec {
        key: "hotkey.toggle_width",
        value_type: ValueType::String,
        default: "\"shift+space\"",
        doc_zh: "全/半角切换：组合键如 shift+space（默认，对齐搜狗/微信） | none = 关闭",
        scope: Scope::Hotkey,
    },
    OptionSpec {
        key: "hotkey.toggle_punctuation",
        value_type: ValueType::String,
        default: "\"ctrl+.\"",
        doc_zh: "中英标点切换：组合键如 ctrl+.（默认，对齐搜狗/微软） | none = 关闭",
        scope: Scope::Hotkey,
    },
    OptionSpec {
        key: "input.punctuation",
        value_type: ValueType::Enum {
            values: &["chinese", "english"],
        },
        default: "\"chinese\"",
        doc_zh: "标点：chinese = 中文 | english = 英文",
        scope: Scope::Engine,
    },
    OptionSpec {
        key: "input.full_width",
        value_type: ValueType::Bool,
        default: "false",
        doc_zh: "全角 ASCII（Shift+Space 可临时切换）",
        scope: Scope::Engine,
    },
];

/// 按键名查找选项（线性扫描，v1 选项）。
pub fn find(key: &str) -> Option<&'static OptionSpec> {
    SCHEMA.iter().find(|spec| spec.key == key)
}
