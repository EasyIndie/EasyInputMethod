//! Canonical hotkey syntax and collision checks for all hosts.
use crate::{Config, ConfigError, Scope, SCHEMA};

/// Platform-neutral shortcut. Modifier bits: ctrl=1, alt=2, shift=4, cmd=8.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Hotkey {
    /// 0=disabled, 1=standalone shift, 2=chord.
    pub kind: u32,
    pub modifiers: u32,
    /// Unicode scalar of the ASCII key; space uses 32.
    pub key: u32,
}

impl Hotkey {
    /// Parse configuration syntax; only the English toggle permits standalone shift.
    pub fn parse(option: &str, value: &str) -> Result<Self, ConfigError> {
        let invalid = || {
            ConfigError::invalid_value(
                option,
                "快捷键应为修饰键+单个字符或space；仅中英切换支持单shift，留空或none关闭",
            )
        };
        let text = value.trim().to_ascii_lowercase();
        if text.is_empty() || text == "none" {
            return Ok(Self {
                kind: 0,
                modifiers: 0,
                key: 0,
            });
        }
        if text == "shift" && option == "hotkey.toggle_english" {
            return Ok(Self {
                kind: 1,
                modifiers: 4,
                key: 0,
            });
        }
        let parts: Vec<_> = text.split('+').map(str::trim).collect();
        if parts.len() < 2 {
            return Err(invalid());
        }
        let mut modifiers = 0;
        for part in &parts[..parts.len() - 1] {
            let bit = match *part {
                "ctrl" | "control" => 1,
                "alt" | "option" => 2,
                "shift" => 4,
                "cmd" | "command" => 8,
                _ => return Err(invalid()),
            };
            if modifiers & bit != 0 {
                return Err(ConfigError::invalid_value(option, "修饰键不能重复"));
            }
            modifiers |= bit;
        }
        let key = parts[parts.len() - 1];
        let key = if key == "space" {
            32
        } else if key.len() == 1 && key.as_bytes()[0].is_ascii_graphic() {
            u32::from(key.as_bytes()[0])
        } else {
            return Err(invalid());
        };
        Ok(Self {
            kind: 2,
            modifiers,
            key,
        })
    }

    /// Stable string used by snapshots and writes; grammar is owned here.
    pub fn canonical(self) -> String {
        match self.kind {
            0 => "none".into(),
            1 => "shift".into(),
            _ => {
                let mut parts: Vec<String> = [(1, "ctrl"), (2, "alt"), (4, "shift"), (8, "cmd")]
                    .into_iter()
                    .filter(|(bit, _)| self.modifiers & bit != 0)
                    .map(|(_, name)| name.to_owned())
                    .collect();
                parts.push(if self.key == 32 {
                    "space".into()
                } else {
                    char::from_u32(self.key)
                        .map(String::from)
                        .unwrap_or_default()
                });
                parts.join("+")
            }
        }
    }
}

pub(crate) fn validate(config: &Config) -> Result<(), ConfigError> {
    let mut seen: Vec<(&str, Hotkey)> = Vec::new();
    for spec in SCHEMA.iter().filter(|spec| spec.scope == Scope::Hotkey) {
        let Some(value) = config.get(spec.key).and_then(|v| v.as_str()) else {
            continue;
        };
        let hotkey = Hotkey::parse(spec.key, value)?;
        if hotkey.kind == 0 {
            continue;
        }
        if let Some((other, _)) = seen.iter().find(|(_, previous)| *previous == hotkey) {
            return Err(ConfigError::invalid_value(
                spec.key,
                format!("快捷键与 {other} 冲突；请修改其中一项或设为none"),
            ));
        }
        seen.push((spec.key, hotkey));
    }
    Ok(())
}
