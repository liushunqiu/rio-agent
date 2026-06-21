use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::str::FromStr;
use uuid::Uuid;

/// Agent 角色枚举
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum AgentRole {
    /// 架构设计师
    Architect,
    /// 代码审查员
    Reviewer,
    /// UI/UX 设计师
    Designer,
    /// 通用助手
    General,
}

impl FromStr for AgentRole {
    type Err = String;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s.to_lowercase().as_str() {
            "architect" => Ok(Self::Architect),
            "reviewer" => Ok(Self::Reviewer),
            "designer" => Ok(Self::Designer),
            "general" => Ok(Self::General),
            _ => Err(format!("Invalid agent role: {}", s)),
        }
    }
}

impl AgentRole {
    /// 获取角色的 System Prompt 片段
    pub fn system_prompt_fragment(&self) -> &'static str {
        match self {
            Self::Architect => {
                "You are an expert software architect specializing in system design, \
                 architectural patterns, and technical decision-making."
            }
            Self::Reviewer => {
                "You are a meticulous code reviewer focusing on correctness, security, \
                 performance, and maintainability."
            }
            Self::Designer => {
                "You are a UI/UX designer with expertise in user experience, \
                 accessibility, and modern design patterns."
            }
            Self::General => {
                "You are a general-purpose AI assistant capable of handling \
                 diverse programming and problem-solving tasks."
            }
        }
    }

    /// 转换为字符串
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Architect => "architect",
            Self::Reviewer => "reviewer",
            Self::Designer => "designer",
            Self::General => "general",
        }
    }
}

/// Agent 身份信息
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentIdentity {
    /// 唯一标识符
    pub id: String,
    /// Agent 名称（如 "XianXian", "Codex"）
    pub name: String,
    /// Agent 角色
    pub role: AgentRole,
    /// 性格描述
    pub personality: String,
    /// AI Provider 名称（"openai", "anthropic", "deepseek" 等）
    pub provider: String,
    /// 模型名称（"gpt-4", "claude-opus-4" 等）
    pub model: String,
    /// 创建时间
    pub created_at: DateTime<Utc>,
}

impl AgentIdentity {
    /// 创建新的 Agent 身份
    pub fn new(
        name: impl Into<String>,
        role: AgentRole,
        personality: impl Into<String>,
        provider: impl Into<String>,
        model: impl Into<String>,
    ) -> Self {
        Self {
            id: Uuid::new_v4().to_string(),
            name: name.into(),
            role,
            personality: personality.into(),
            provider: provider.into(),
            model: model.into(),
            created_at: Utc::now(),
        }
    }

    /// 构建完整的 System Prompt（身份 + 角色）
    pub fn build_system_prompt(&self) -> String {
        format!(
            "# Agent Identity\n\
             You are {}, a {} agent.\n\
             Personality: {}\n\n\
             # Role Description\n\
             {}\n",
            self.name,
            self.role.as_str(),
            self.personality,
            self.role.system_prompt_fragment()
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_agent_role_from_str() {
        assert_eq!("architect".parse::<AgentRole>(), Ok(AgentRole::Architect));
        assert_eq!("REVIEWER".parse::<AgentRole>(), Ok(AgentRole::Reviewer));
        assert_eq!("Designer".parse::<AgentRole>(), Ok(AgentRole::Designer));
        assert_eq!("general".parse::<AgentRole>(), Ok(AgentRole::General));
        assert!("unknown".parse::<AgentRole>().is_err());
    }

    #[test]
    fn test_agent_role_as_str() {
        assert_eq!(AgentRole::Architect.as_str(), "architect");
        assert_eq!(AgentRole::Reviewer.as_str(), "reviewer");
        assert_eq!(AgentRole::Designer.as_str(), "designer");
        assert_eq!(AgentRole::General.as_str(), "general");
    }

    #[test]
    fn test_agent_identity_creation() {
        let identity = AgentIdentity::new(
            "TestAgent",
            AgentRole::Architect,
            "Thoughtful and detail-oriented",
            "anthropic",
            "claude-opus-4",
        );

        assert_eq!(identity.name, "TestAgent");
        assert_eq!(identity.role, AgentRole::Architect);
        assert_eq!(identity.personality, "Thoughtful and detail-oriented");
        assert_eq!(identity.provider, "anthropic");
        assert_eq!(identity.model, "claude-opus-4");
        assert!(!identity.id.is_empty());
    }

    #[test]
    fn test_build_system_prompt() {
        let identity = AgentIdentity::new(
            "XianXian",
            AgentRole::Reviewer,
            "Meticulous and constructive",
            "anthropic",
            "claude-opus-4",
        );

        let prompt = identity.build_system_prompt();
        assert!(prompt.contains("You are XianXian"));
        assert!(prompt.contains("reviewer agent"));
        assert!(prompt.contains("Meticulous and constructive"));
        assert!(prompt.contains("code reviewer"));
    }

    #[test]
    fn test_agent_role_system_prompt() {
        let architect_prompt = AgentRole::Architect.system_prompt_fragment();
        assert!(architect_prompt.contains("architect"));
        assert!(architect_prompt.contains("system design"));

        let reviewer_prompt = AgentRole::Reviewer.system_prompt_fragment();
        assert!(reviewer_prompt.contains("code reviewer"));
        assert!(reviewer_prompt.contains("security"));
    }
}
