//! 不可变配置快照：Schema 默认值与文件值合并。
//!
//! 读取侧零拷贝：组件只拿 `Arc<Config>` / 引用，不各自缓存副本（铁律 R2）。

use std::collections::BTreeMap;
use std::fmt;

use crate::schema::{self, OptionSpec, ValueType};
use crate::ConfigError;

/// 一个配置值（有限类型，与 TOML 标量对应）。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ConfigValue {
    Bool(bool),
    Int(i64),
    String(String),
}

impl ConfigValue {
    pub fn as_bool(&self) -> Option<bool> {
        match self {
            Self::Bool(v) => Some(*v),
            _ => None,
        }
    }

    pub fn as_int(&self) -> Option<i64> {
        match self {
            Self::Int(v) => Some(*v),
            _ => None,
        }
    }

    pub fn as_str(&self) -> Option<&str> {
        match self {
            Self::String(v) => Some(v),
            _ => None,
        }
    }
}

impl fmt::Display for ConfigValue {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Bool(v) => write!(f, "{v}"),
            Self::Int(v) => write!(f, "{v}"),
            Self::String(v) => write!(f, "{v}"),
        }
    }
}

/// 不可变配置快照。
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct Config {
    values: BTreeMap<&'static str, ConfigValue>,
}

impl Config {
    /// 由 Schema 默认值构造（唯一出处，见 `schema::SCHEMA`）。
    pub fn defaults() -> Self {
        let mut values = BTreeMap::new();
        for spec in schema::SCHEMA {
            // 默认字面量由 schema 编写者保证合法；失败时跳过该键（库内不 panic）。
            if let Ok(value) = parse_literal(spec, spec.default) {
                values.insert(spec.key, value);
            }
        }
        Self { values }
    }

    /// 按键取当前值。
    pub fn get(&self, key: &str) -> Option<&ConfigValue> {
        self.values.get(key)
    }

    /// 迭代 `(key, value)`（键按字典序）。
    pub fn iter(&self) -> impl Iterator<Item = (&'static str, &ConfigValue)> {
        self.values.iter().map(|(k, v)| (*k, v))
    }

    /// 插入一个已校验的值（仅 crate 内部使用）。
    pub(crate) fn insert(&mut self, key: &'static str, value: ConfigValue) {
        self.values.insert(key, value);
    }
}

/// 按 Schema 解析一个 TOML 字面量（`set` 的入参形式）。
pub(crate) fn parse_literal(spec: &OptionSpec, raw: &str) -> Result<ConfigValue, ConfigError> {
    let raw = raw.trim();
    match spec.value_type {
        ValueType::Bool => match raw {
            "true" => Ok(ConfigValue::Bool(true)),
            "false" => Ok(ConfigValue::Bool(false)),
            _ => Err(ConfigError::invalid_value(spec.key, "期望 true 或 false")),
        },
        ValueType::Int { min, max } => {
            let n: i64 = raw
                .parse()
                .map_err(|_| ConfigError::invalid_value(spec.key, "期望整数"))?;
            if (min..=max).contains(&n) {
                Ok(ConfigValue::Int(n))
            } else {
                Err(ConfigError::invalid_value(
                    spec.key,
                    format!("超出范围 [{min}, {max}]"),
                ))
            }
        }
        ValueType::Enum { values } => {
            let s = unquote(raw);
            if values.contains(&s.as_str()) {
                Ok(ConfigValue::String(s))
            } else {
                Err(ConfigError::invalid_value(
                    spec.key,
                    format!("期望 {}", values.join(" | ")),
                ))
            }
        }
        ValueType::String => string_value(spec, &unquote(raw)),
        ValueType::Url => url_value(spec, &unquote(raw)),
    }
}

/// 去掉可选的成对双引号，兼容 `"wildcard"` 与 `wildcard` 两种写法。
fn unquote(raw: &str) -> String {
    let raw = raw.trim();
    if raw.len() >= 2 && raw.starts_with('"') && raw.ends_with('"') {
        raw[1..raw.len() - 1].to_string()
    } else {
        raw.to_string()
    }
}

/// 空值或 https URL；拒绝凭据与 fragment，避免把更新源写进日志或误导用户。
pub(crate) fn url_value(spec: &OptionSpec, value: &str) -> Result<ConfigValue, ConfigError> {
    if value.is_empty() {
        return Ok(ConfigValue::String(String::new()));
    }
    let valid = value.starts_with("https://")
        && !value.contains(char::is_whitespace)
        && !value.contains('@')
        && !value.contains('#')
        && value["https://".len()..]
            .split('/')
            .next()
            .is_some_and(|host| !host.is_empty());
    if valid {
        Ok(ConfigValue::String(value.to_owned()))
    } else {
        Err(ConfigError::invalid_value(
            spec.key,
            "期望空值或 https URL（不含凭据/fragment）",
        ))
    }
}

/// Validate and normalize string values from both setters and file loads.
pub(crate) fn string_value(spec: &OptionSpec, value: &str) -> Result<ConfigValue, ConfigError> {
    if spec.scope == schema::Scope::Hotkey {
        Ok(ConfigValue::String(
            crate::Hotkey::parse(spec.key, value)?.canonical(),
        ))
    } else if spec.value_type == ValueType::Url {
        url_value(spec, value)
    } else {
        Ok(ConfigValue::String(value.to_owned()))
    }
}
