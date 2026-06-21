use regex::Regex;
use std::sync::OnceLock;

/// @mention 解析结果
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum MentionTarget {
    /// 单个 Agent（@agentName）
    Single(String),
    /// 多个 Agent（@agent1 @agent2）
    Multiple(Vec<String>),
    /// 广播到所有 Agent（@all）
    Broadcast,
}

/// @mention 解析器
pub struct MentionParser;

impl MentionParser {
    /// 解析用户输入中的 @mention
    ///
    /// # 支持的格式
    /// - `@agentName` - 单个 Agent
    /// - `@agent1 @agent2` - 多个 Agent
    /// - `@all` - 广播到所有 Agent
    ///
    /// # 返回
    /// - `Some(MentionTarget)` - 找到 @mention
    /// - `None` - 没有 @mention
    pub fn parse(input: &str) -> Option<MentionTarget> {
        static MENTION_REGEX: OnceLock<Regex> = OnceLock::new();
        let re = MENTION_REGEX.get_or_init(|| {
            // 匹配 @xxx（字母、数字、下划线、连字符）
            Regex::new(r"@([a-zA-Z0-9_-]+)").unwrap()
        });

        let mentions: Vec<String> = re
            .captures_iter(input)
            .map(|cap| cap[1].to_lowercase())
            .collect();

        if mentions.is_empty() {
            return None;
        }

        // 检查是否包含 @all
        if mentions.iter().any(|m| m == "all") {
            return Some(MentionTarget::Broadcast);
        }

        // 去重
        let unique_mentions: Vec<String> = mentions
            .into_iter()
            .collect::<std::collections::HashSet<_>>()
            .into_iter()
            .collect();

        if unique_mentions.len() == 1 {
            Some(MentionTarget::Single(unique_mentions[0].clone()))
        } else {
            Some(MentionTarget::Multiple(unique_mentions))
        }
    }

    /// 从输入中移除 @mention
    pub fn strip_mentions(input: &str) -> String {
        static MENTION_REGEX: OnceLock<Regex> = OnceLock::new();
        let re = MENTION_REGEX.get_or_init(|| {
            Regex::new(r"@([a-zA-Z0-9_-]+)\s*").unwrap()
        });

        re.replace_all(input, "").trim().to_string()
    }

    /// 验证 Agent 名称是否有效
    pub fn is_valid_agent_name(name: &str) -> bool {
        static NAME_REGEX: OnceLock<Regex> = OnceLock::new();
        let re = NAME_REGEX.get_or_init(|| {
            // 只允许字母、数字、下划线、连字符，长度 1-32
            Regex::new(r"^[a-zA-Z0-9_-]{1,32}$").unwrap()
        });

        re.is_match(name)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_single_mention() {
        let result = MentionParser::parse("@opus help me with this");
        assert_eq!(result, Some(MentionTarget::Single("opus".to_string())));
    }

    #[test]
    fn test_parse_multiple_mentions() {
        let result = MentionParser::parse("@opus @codex review this code");
        match result {
            Some(MentionTarget::Multiple(agents)) => {
                assert_eq!(agents.len(), 2);
                assert!(agents.contains(&"opus".to_string()));
                assert!(agents.contains(&"codex".to_string()));
            }
            _ => panic!("Expected Multiple"),
        }
    }

    #[test]
    fn test_parse_broadcast() {
        let result = MentionParser::parse("@all everyone look at this");
        assert_eq!(result, Some(MentionTarget::Broadcast));
    }

    #[test]
    fn test_parse_duplicate_mentions() {
        let result = MentionParser::parse("@opus @opus help");
        assert_eq!(result, Some(MentionTarget::Single("opus".to_string())));
    }

    #[test]
    fn test_parse_no_mention() {
        let result = MentionParser::parse("No mentions here");
        assert_eq!(result, None);
    }

    #[test]
    fn test_parse_case_insensitive() {
        let result = MentionParser::parse("@Opus @CODEX");
        match result {
            Some(MentionTarget::Multiple(agents)) => {
                assert_eq!(agents.len(), 2);
                assert!(agents.contains(&"opus".to_string()));
                assert!(agents.contains(&"codex".to_string()));
            }
            _ => panic!("Expected Multiple"),
        }
    }

    #[test]
    fn test_parse_hyphen_underscore() {
        let result = MentionParser::parse("@test-agent @another_one");
        match result {
            Some(MentionTarget::Multiple(agents)) => {
                assert_eq!(agents.len(), 2);
                assert!(agents.contains(&"test-agent".to_string()));
                assert!(agents.contains(&"another_one".to_string()));
            }
            _ => panic!("Expected Multiple"),
        }
    }

    #[test]
    fn test_broadcast_overrides_specific() {
        let result = MentionParser::parse("@opus @all @codex");
        assert_eq!(result, Some(MentionTarget::Broadcast));
    }

    #[test]
    fn test_strip_mentions() {
        let stripped = MentionParser::strip_mentions("@opus @codex review this code");
        assert_eq!(stripped, "review this code");
    }

    #[test]
    fn test_strip_mentions_preserves_content() {
        let stripped = MentionParser::strip_mentions("@opus help with @mentions in text");
        assert_eq!(stripped, "help with in text");
    }

    #[test]
    fn test_is_valid_agent_name() {
        assert!(MentionParser::is_valid_agent_name("opus"));
        assert!(MentionParser::is_valid_agent_name("test-agent"));
        assert!(MentionParser::is_valid_agent_name("agent_123"));
        assert!(MentionParser::is_valid_agent_name("A1"));

        // Invalid cases
        assert!(!MentionParser::is_valid_agent_name(""));
        assert!(!MentionParser::is_valid_agent_name("agent with spaces"));
        assert!(!MentionParser::is_valid_agent_name("agent@special"));
        assert!(!MentionParser::is_valid_agent_name("a".repeat(33).as_str()));
    }
}
