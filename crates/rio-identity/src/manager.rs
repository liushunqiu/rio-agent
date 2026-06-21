use crate::identity::{AgentIdentity, AgentRole};
use anyhow::{anyhow, Context, Result};
use chrono::{DateTime, Utc};
use sqlx::{Row, SqlitePool};

/// Agent 身份管理器
pub struct IdentityManager {
    pool: SqlitePool,
}

impl IdentityManager {
    /// 创建新的身份管理器
    pub async fn new(pool: SqlitePool) -> Result<Self> {
        let manager = Self { pool };
        manager.init_schema().await?;
        Ok(manager)
    }

    /// 初始化数据库 Schema（Migration 001）
    async fn init_schema(&self) -> Result<()> {
        sqlx::query(
            r#"
            CREATE TABLE IF NOT EXISTS agent_identities (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                role TEXT NOT NULL,
                personality TEXT NOT NULL,
                provider TEXT NOT NULL,
                model TEXT NOT NULL,
                created_at TEXT NOT NULL
            )
            "#,
        )
        .execute(&self.pool)
        .await
        .context("Failed to create agent_identities table")?;

        // 创建索引以优化查询性能
        sqlx::query("CREATE INDEX IF NOT EXISTS idx_agent_name ON agent_identities(name)")
            .execute(&self.pool)
            .await
            .context("Failed to create name index")?;

        sqlx::query("CREATE INDEX IF NOT EXISTS idx_agent_role ON agent_identities(role)")
            .execute(&self.pool)
            .await
            .context("Failed to create role index")?;

        Ok(())
    }

    /// 创建新的 Agent 身份
    pub async fn create(&self, identity: &AgentIdentity) -> Result<()> {
        // 检查 ID 是否已存在
        if self.get(&identity.id).await?.is_some() {
            return Err(anyhow!("Agent identity with ID {} already exists", identity.id));
        }

        // 检查名称是否已存在
        if self.get_by_name(&identity.name).await?.is_some() {
            return Err(anyhow!("Agent identity with name '{}' already exists", identity.name));
        }

        sqlx::query(
            r#"
            INSERT INTO agent_identities (id, name, role, personality, provider, model, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            "#,
        )
        .bind(&identity.id)
        .bind(&identity.name)
        .bind(identity.role.as_str())
        .bind(&identity.personality)
        .bind(&identity.provider)
        .bind(&identity.model)
        .bind(identity.created_at.to_rfc3339())
        .execute(&self.pool)
        .await
        .context("Failed to insert agent identity")?;

        Ok(())
    }

    /// 根据 ID 获取 Agent 身份
    pub async fn get(&self, id: &str) -> Result<Option<AgentIdentity>> {
        let row = sqlx::query(
            r#"
            SELECT id, name, role, personality, provider, model, created_at
            FROM agent_identities
            WHERE id = ?
            "#,
        )
        .bind(id)
        .fetch_optional(&self.pool)
        .await
        .context("Failed to query agent identity")?;

        if let Some(row) = row {
            let identity = self.row_to_identity(&row)?;
            Ok(Some(identity))
        } else {
            Ok(None)
        }
    }

    /// 根据名称获取 Agent 身份
    pub async fn get_by_name(&self, name: &str) -> Result<Option<AgentIdentity>> {
        let row = sqlx::query(
            r#"
            SELECT id, name, role, personality, provider, model, created_at
            FROM agent_identities
            WHERE name = ?
            "#,
        )
        .bind(name)
        .fetch_optional(&self.pool)
        .await
        .context("Failed to query agent identity by name")?;

        if let Some(row) = row {
            let identity = self.row_to_identity(&row)?;
            Ok(Some(identity))
        } else {
            Ok(None)
        }
    }

    /// 列出所有 Agent 身份
    pub async fn list(&self) -> Result<Vec<AgentIdentity>> {
        let rows = sqlx::query(
            r#"
            SELECT id, name, role, personality, provider, model, created_at
            FROM agent_identities
            ORDER BY created_at DESC
            "#,
        )
        .fetch_all(&self.pool)
        .await
        .context("Failed to list agent identities")?;

        let mut identities = Vec::new();
        for row in rows {
            identities.push(self.row_to_identity(&row)?);
        }

        Ok(identities)
    }

    /// 根据角色筛选 Agent 身份
    pub async fn list_by_role(&self, role: AgentRole) -> Result<Vec<AgentIdentity>> {
        let rows = sqlx::query(
            r#"
            SELECT id, name, role, personality, provider, model, created_at
            FROM agent_identities
            WHERE role = ?
            ORDER BY created_at DESC
            "#,
        )
        .bind(role.as_str())
        .fetch_all(&self.pool)
        .await
        .context("Failed to list agent identities by role")?;

        let mut identities = Vec::new();
        for row in rows {
            identities.push(self.row_to_identity(&row)?);
        }

        Ok(identities)
    }

    /// 更新 Agent 身份
    pub async fn update(&self, identity: &AgentIdentity) -> Result<()> {
        // 检查 ID 是否存在
        if self.get(&identity.id).await?.is_none() {
            return Err(anyhow!("Agent identity with ID {} not found", identity.id));
        }

        // 检查名称冲突（排除自身）
        if let Some(existing) = self.get_by_name(&identity.name).await? {
            if existing.id != identity.id {
                return Err(anyhow!(
                    "Agent identity with name '{}' already exists",
                    identity.name
                ));
            }
        }

        let rows_affected = sqlx::query(
            r#"
            UPDATE agent_identities
            SET name = ?, role = ?, personality = ?, provider = ?, model = ?
            WHERE id = ?
            "#,
        )
        .bind(&identity.name)
        .bind(identity.role.as_str())
        .bind(&identity.personality)
        .bind(&identity.provider)
        .bind(&identity.model)
        .bind(&identity.id)
        .execute(&self.pool)
        .await
        .context("Failed to update agent identity")?
        .rows_affected();

        if rows_affected == 0 {
            return Err(anyhow!("No agent identity updated"));
        }

        Ok(())
    }

    /// 删除 Agent 身份
    pub async fn delete(&self, id: &str) -> Result<()> {
        let rows_affected = sqlx::query(
            r#"
            DELETE FROM agent_identities
            WHERE id = ?
            "#,
        )
        .bind(id)
        .execute(&self.pool)
        .await
        .context("Failed to delete agent identity")?
        .rows_affected();

        if rows_affected == 0 {
            return Err(anyhow!("Agent identity with ID {} not found", id));
        }

        Ok(())
    }

    /// 将数据库行转换为 AgentIdentity
    fn row_to_identity(&self, row: &sqlx::sqlite::SqliteRow) -> Result<AgentIdentity> {
        let id: String = row.get("id");
        let role_str: String = row.get("role");
        let role = role_str.parse::<AgentRole>()
            .map_err(|e| anyhow!("Invalid role '{}' for agent {}: {}", role_str, id, e))?;

        let created_at_str: String = row.get("created_at");
        let created_at = DateTime::parse_from_rfc3339(&created_at_str)
            .with_context(|| format!("Failed to parse created_at for agent {}", id))?
            .with_timezone(&Utc);

        Ok(AgentIdentity {
            id: id.clone(),
            name: row.get("name"),
            role,
            personality: row.get("personality"),
            provider: row.get("provider"),
            model: row.get("model"),
            created_at,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    async fn create_test_manager() -> Result<IdentityManager> {
        let pool = SqlitePool::connect(":memory:").await?;
        IdentityManager::new(pool).await
    }

    #[tokio::test]
    async fn test_create_and_get_identity() -> Result<()> {
        let manager = create_test_manager().await?;

        let identity = AgentIdentity::new(
            "TestAgent",
            AgentRole::Architect,
            "Thoughtful and detail-oriented",
            "anthropic",
            "claude-opus-4",
        );

        // 创建身份
        manager.create(&identity).await?;

        // 通过 ID 获取
        let retrieved = manager.get(&identity.id).await?;
        assert!(retrieved.is_some());
        let retrieved = retrieved.unwrap();
        assert_eq!(retrieved.name, identity.name);
        assert_eq!(retrieved.role, identity.role);

        // 通过名称获取
        let retrieved_by_name = manager.get_by_name("TestAgent").await?;
        assert!(retrieved_by_name.is_some());
        assert_eq!(retrieved_by_name.unwrap().id, identity.id);

        Ok(())
    }

    #[tokio::test]
    async fn test_duplicate_id_rejected() -> Result<()> {
        let manager = create_test_manager().await?;

        let mut identity1 = AgentIdentity::new(
            "Agent1",
            AgentRole::Reviewer,
            "Meticulous",
            "openai",
            "gpt-4",
        );

        manager.create(&identity1).await?;

        // 尝试创建相同 ID 的身份
        identity1.name = "Agent2".to_string();
        let result = manager.create(&identity1).await;
        assert!(result.is_err());
        assert!(result.unwrap_err().to_string().contains("already exists"));

        Ok(())
    }

    #[tokio::test]
    async fn test_duplicate_name_rejected() -> Result<()> {
        let manager = create_test_manager().await?;

        let identity1 = AgentIdentity::new(
            "DuplicateName",
            AgentRole::Reviewer,
            "First",
            "openai",
            "gpt-4",
        );

        manager.create(&identity1).await?;

        // 尝试创建相同名称的身份
        let identity2 = AgentIdentity::new(
            "DuplicateName",
            AgentRole::Designer,
            "Second",
            "anthropic",
            "claude-opus-4",
        );

        let result = manager.create(&identity2).await;
        assert!(result.is_err());
        assert!(result.unwrap_err().to_string().contains("already exists"));

        Ok(())
    }

    #[tokio::test]
    async fn test_list_identities() -> Result<()> {
        let manager = create_test_manager().await?;

        // 创建多个身份
        let identity1 = AgentIdentity::new(
            "Agent1",
            AgentRole::Architect,
            "Creative",
            "anthropic",
            "claude-opus-4",
        );
        let identity2 = AgentIdentity::new(
            "Agent2",
            AgentRole::Reviewer,
            "Critical",
            "openai",
            "gpt-4",
        );

        manager.create(&identity1).await?;
        manager.create(&identity2).await?;

        // 列出所有身份
        let all = manager.list().await?;
        assert_eq!(all.len(), 2);

        Ok(())
    }

    #[tokio::test]
    async fn test_list_by_role() -> Result<()> {
        let manager = create_test_manager().await?;

        let identity1 = AgentIdentity::new(
            "Architect1",
            AgentRole::Architect,
            "Visionary",
            "anthropic",
            "claude-opus-4",
        );
        let identity2 = AgentIdentity::new(
            "Reviewer1",
            AgentRole::Reviewer,
            "Thorough",
            "openai",
            "gpt-4",
        );
        let identity3 = AgentIdentity::new(
            "Architect2",
            AgentRole::Architect,
            "Pragmatic",
            "deepseek",
            "deepseek-chat",
        );

        manager.create(&identity1).await?;
        manager.create(&identity2).await?;
        manager.create(&identity3).await?;

        // 按角色筛选
        let architects = manager.list_by_role(AgentRole::Architect).await?;
        assert_eq!(architects.len(), 2);

        let reviewers = manager.list_by_role(AgentRole::Reviewer).await?;
        assert_eq!(reviewers.len(), 1);

        Ok(())
    }

    #[tokio::test]
    async fn test_update_identity() -> Result<()> {
        let manager = create_test_manager().await?;

        let mut identity = AgentIdentity::new(
            "OriginalName",
            AgentRole::General,
            "Original personality",
            "anthropic",
            "claude-opus-4",
        );

        manager.create(&identity).await?;

        // 更新身份
        identity.name = "UpdatedName".to_string();
        identity.personality = "Updated personality".to_string();
        identity.model = "claude-sonnet-4".to_string();

        manager.update(&identity).await?;

        // 验证更新
        let updated = manager.get(&identity.id).await?;
        assert!(updated.is_some());
        let updated = updated.unwrap();
        assert_eq!(updated.name, "UpdatedName");
        assert_eq!(updated.personality, "Updated personality");
        assert_eq!(updated.model, "claude-sonnet-4");

        Ok(())
    }

    #[tokio::test]
    async fn test_update_nonexistent_identity() -> Result<()> {
        let manager = create_test_manager().await?;

        let identity = AgentIdentity::new(
            "Nonexistent",
            AgentRole::General,
            "Test",
            "anthropic",
            "claude-opus-4",
        );

        let result = manager.update(&identity).await;
        assert!(result.is_err());
        assert!(result.unwrap_err().to_string().contains("not found"));

        Ok(())
    }

    #[tokio::test]
    async fn test_delete_identity() -> Result<()> {
        let manager = create_test_manager().await?;

        let identity = AgentIdentity::new(
            "ToDelete",
            AgentRole::General,
            "Temporary",
            "anthropic",
            "claude-opus-4",
        );

        manager.create(&identity).await?;

        // 删除身份
        manager.delete(&identity.id).await?;

        // 验证已删除
        let retrieved = manager.get(&identity.id).await?;
        assert!(retrieved.is_none());

        Ok(())
    }

    #[tokio::test]
    async fn test_delete_nonexistent_identity() -> Result<()> {
        let manager = create_test_manager().await?;

        let result = manager.delete("nonexistent-id").await;
        assert!(result.is_err());
        assert!(result.unwrap_err().to_string().contains("not found"));

        Ok(())
    }
}
