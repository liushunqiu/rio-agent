use anyhow::{Result, Context};
use chrono::{DateTime, Utc};
use rio_core::Message;
use serde::{Deserialize, Serialize};
use sqlx::{SqlitePool, Row};
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Session {
    pub id: String,
    pub title: String,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Configuration {
    pub id: String,
    pub name: String,
    pub provider: String,  // "claude", "openai", "gemini", "deepseek"
    pub model: String,
    pub endpoint: Option<String>,
    pub is_active: bool,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

pub struct Storage {
    pool: SqlitePool,
}

impl Storage {
    pub async fn new(database_url: &str) -> Result<Self> {
        let pool = SqlitePool::connect(database_url).await?;

        let storage = Self { pool };
        storage.init_schema().await?;

        Ok(storage)
    }

    async fn init_schema(&self) -> Result<()> {
        sqlx::query(
            r#"
            CREATE TABLE IF NOT EXISTS sessions (
                id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            )
            "#
        )
        .execute(&self.pool)
        .await?;

        sqlx::query(
            r#"
            CREATE TABLE IF NOT EXISTS messages (
                id TEXT PRIMARY KEY,
                session_id TEXT NOT NULL,
                role TEXT NOT NULL,
                content TEXT NOT NULL,
                tool_calls TEXT,
                tool_call_id TEXT,
                created_at TEXT NOT NULL,
                FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
            )
            "#
        )
        .execute(&self.pool)
        .await?;

        sqlx::query(
            r#"
            CREATE INDEX IF NOT EXISTS idx_messages_session_id
            ON messages(session_id)
            "#
        )
        .execute(&self.pool)
        .await?;

        // 配置表：存储 AI Provider 配置（API key 存在 OS Keychain）
        sqlx::query(
            r#"
            CREATE TABLE IF NOT EXISTS configurations (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL UNIQUE,
                provider TEXT NOT NULL,
                model TEXT NOT NULL,
                endpoint TEXT,
                is_active INTEGER NOT NULL DEFAULT 0,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            )
            "#
        )
        .execute(&self.pool)
        .await?;

        Ok(())
    }

    pub async fn create_session(&self, title: impl Into<String>) -> Result<Session> {
        let session = Session {
            id: Uuid::new_v4().to_string(),
            title: title.into(),
            created_at: Utc::now(),
            updated_at: Utc::now(),
        };

        sqlx::query(
            r#"
            INSERT INTO sessions (id, title, created_at, updated_at)
            VALUES (?, ?, ?, ?)
            "#
        )
        .bind(&session.id)
        .bind(&session.title)
        .bind(session.created_at.to_rfc3339())
        .bind(session.updated_at.to_rfc3339())
        .execute(&self.pool)
        .await?;

        Ok(session)
    }

    pub async fn get_session(&self, session_id: &str) -> Result<Option<Session>> {
        let row = sqlx::query(
            r#"
            SELECT id, title, created_at, updated_at
            FROM sessions
            WHERE id = ?
            "#
        )
        .bind(session_id)
        .fetch_optional(&self.pool)
        .await?;

        if let Some(row) = row {
            let session_id: String = row.get("id");
            Ok(Some(Session {
                id: session_id.clone(),
                title: row.get("title"),
                created_at: DateTime::parse_from_rfc3339(row.get("created_at"))
                    .with_context(|| format!("Failed to parse created_at for session {}", session_id))?
                    .with_timezone(&Utc),
                updated_at: DateTime::parse_from_rfc3339(row.get("updated_at"))
                    .with_context(|| format!("Failed to parse updated_at for session {}", session_id))?
                    .with_timezone(&Utc),
            }))
        } else {
            Ok(None)
        }
    }

    pub async fn list_sessions(&self) -> Result<Vec<Session>> {
        let rows = sqlx::query(
            r#"
            SELECT id, title, created_at, updated_at
            FROM sessions
            ORDER BY updated_at DESC
            "#
        )
        .fetch_all(&self.pool)
        .await?;

        let mut sessions = Vec::new();
        for row in rows {
            let session_id: String = row.get("id");
            sessions.push(Session {
                id: session_id.clone(),
                title: row.get("title"),
                created_at: DateTime::parse_from_rfc3339(row.get("created_at"))
                    .with_context(|| format!("Failed to parse created_at for session {}", session_id))?
                    .with_timezone(&Utc),
                updated_at: DateTime::parse_from_rfc3339(row.get("updated_at"))
                    .with_context(|| format!("Failed to parse updated_at for session {}", session_id))?
                    .with_timezone(&Utc),
            });
        }

        Ok(sessions)
    }

    pub async fn save_message(&self, session_id: &str, message: &Message) -> Result<()> {
        let tool_calls_json = message.tool_calls.as_ref()
            .map(serde_json::to_string)
            .transpose()?;

        let role_str = match message.role {
            rio_core::Role::User => "user",
            rio_core::Role::Assistant => "assistant",
            rio_core::Role::System => "system",
        };

        sqlx::query(
            r#"
            INSERT INTO messages (id, session_id, role, content, tool_calls, tool_call_id, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            "#
        )
        .bind(&message.id)
        .bind(session_id)
        .bind(role_str)
        .bind(&message.content)
        .bind(tool_calls_json)
        .bind(&message.tool_call_id)
        .bind(message.created_at.to_rfc3339())
        .execute(&self.pool)
        .await?;

        sqlx::query(
            r#"
            UPDATE sessions
            SET updated_at = ?
            WHERE id = ?
            "#
        )
        .bind(Utc::now().to_rfc3339())
        .bind(session_id)
        .execute(&self.pool)
        .await?;

        Ok(())
    }

    pub async fn get_messages(&self, session_id: &str) -> Result<Vec<Message>> {
        let rows = sqlx::query(
            r#"
            SELECT id, role, content, tool_calls, tool_call_id, created_at
            FROM messages
            WHERE session_id = ?
            ORDER BY created_at ASC
            "#
        )
        .bind(session_id)
        .fetch_all(&self.pool)
        .await?;

        let mut messages = Vec::new();
        for row in rows {
            let message_id: String = row.get("id");
            let role_str: String = row.get("role");
            let role = match role_str.as_str() {
                "user" => rio_core::Role::User,
                "assistant" => rio_core::Role::Assistant,
                "system" => rio_core::Role::System,
                _ => rio_core::Role::User,
            };

            let tool_calls: Option<String> = row.get("tool_calls");
            let tool_calls_parsed = tool_calls
                .and_then(|json| serde_json::from_str(&json).ok());

            messages.push(Message {
                id: message_id.clone(),
                role,
                content: row.get("content"),
                tool_calls: tool_calls_parsed,
                tool_call_id: row.get("tool_call_id"),
                created_at: DateTime::parse_from_rfc3339(row.get("created_at"))
                    .with_context(|| format!("Failed to parse created_at for message {} in session {}", message_id, session_id))?
                    .with_timezone(&Utc),
            });
        }

        Ok(messages)
    }

    /// 删除会话及其所有消息
    pub async fn delete_session(&self, session_id: &str) -> Result<()> {
        // 先删除消息（外键约束）
        sqlx::query("DELETE FROM messages WHERE session_id = ?")
            .bind(session_id)
            .execute(&self.pool)
            .await?;

        // 再删除会话
        sqlx::query("DELETE FROM sessions WHERE id = ?")
            .bind(session_id)
            .execute(&self.pool)
            .await?;

        Ok(())
    }

    /// 更新会话标题
    pub async fn update_session_title(&self, session_id: &str, title: &str) -> Result<()> {
        sqlx::query(
            r#"
            UPDATE sessions
            SET title = ?, updated_at = ?
            WHERE id = ?
            "#
        )
        .bind(title)
        .bind(Utc::now().to_rfc3339())
        .bind(session_id)
        .execute(&self.pool)
        .await?;

        Ok(())
    }

    /// 删除会话的所有消息
    pub async fn clear_messages(&self, session_id: &str) -> Result<()> {
        sqlx::query("DELETE FROM messages WHERE session_id = ?")
            .bind(session_id)
            .execute(&self.pool)
            .await?;

        // 更新会话时间戳
        sqlx::query(
            r#"
            UPDATE sessions
            SET updated_at = ?
            WHERE id = ?
            "#
        )
        .bind(Utc::now().to_rfc3339())
        .bind(session_id)
        .execute(&self.pool)
        .await?;

        Ok(())
    }

    // ==================== 配置管理 ====================

    /// 创建配置
    pub async fn create_configuration(
        &self,
        name: &str,
        provider: &str,
        model: &str,
        endpoint: Option<&str>,
    ) -> Result<Configuration> {
        let config = Configuration {
            id: Uuid::new_v4().to_string(),
            name: name.to_string(),
            provider: provider.to_string(),
            model: model.to_string(),
            endpoint: endpoint.map(|s| s.to_string()),
            is_active: false,
            created_at: Utc::now(),
            updated_at: Utc::now(),
        };

        sqlx::query(
            r#"
            INSERT INTO configurations (id, name, provider, model, endpoint, is_active, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            "#
        )
        .bind(&config.id)
        .bind(&config.name)
        .bind(&config.provider)
        .bind(&config.model)
        .bind(&config.endpoint)
        .bind(config.is_active as i64)
        .bind(config.created_at.to_rfc3339())
        .bind(config.updated_at.to_rfc3339())
        .execute(&self.pool)
        .await?;

        Ok(config)
    }

    /// 获取所有配置
    pub async fn list_configurations(&self) -> Result<Vec<Configuration>> {
        let rows = sqlx::query(
            r#"
            SELECT id, name, provider, model, endpoint, is_active, created_at, updated_at
            FROM configurations
            ORDER BY created_at DESC
            "#
        )
        .fetch_all(&self.pool)
        .await?;

        let mut configs = Vec::new();
        for row in rows {
            let config_id: String = row.get("id");
            configs.push(Configuration {
                id: config_id.clone(),
                name: row.get("name"),
                provider: row.get("provider"),
                model: row.get("model"),
                endpoint: row.get("endpoint"),
                is_active: row.get::<i64, _>("is_active") != 0,
                created_at: DateTime::parse_from_rfc3339(row.get("created_at"))
                    .with_context(|| format!("Failed to parse created_at for config {}", config_id))?
                    .with_timezone(&Utc),
                updated_at: DateTime::parse_from_rfc3339(row.get("updated_at"))
                    .with_context(|| format!("Failed to parse updated_at for config {}", config_id))?
                    .with_timezone(&Utc),
            });
        }

        Ok(configs)
    }

    /// 获取单个配置
    pub async fn get_configuration(&self, config_id: &str) -> Result<Option<Configuration>> {
        let row = sqlx::query(
            r#"
            SELECT id, name, provider, model, endpoint, is_active, created_at, updated_at
            FROM configurations
            WHERE id = ?
            "#
        )
        .bind(config_id)
        .fetch_optional(&self.pool)
        .await?;

        if let Some(row) = row {
            let config_id: String = row.get("id");
            Ok(Some(Configuration {
                id: config_id.clone(),
                name: row.get("name"),
                provider: row.get("provider"),
                model: row.get("model"),
                endpoint: row.get("endpoint"),
                is_active: row.get::<i64, _>("is_active") != 0,
                created_at: DateTime::parse_from_rfc3339(row.get("created_at"))
                    .with_context(|| format!("Failed to parse created_at for config {}", config_id))?
                    .with_timezone(&Utc),
                updated_at: DateTime::parse_from_rfc3339(row.get("updated_at"))
                    .with_context(|| format!("Failed to parse updated_at for config {}", config_id))?
                    .with_timezone(&Utc),
            }))
        } else {
            Ok(None)
        }
    }

    /// 获取当前激活的配置
    pub async fn get_active_configuration(&self) -> Result<Option<Configuration>> {
        let row = sqlx::query(
            r#"
            SELECT id, name, provider, model, endpoint, is_active, created_at, updated_at
            FROM configurations
            WHERE is_active = 1
            LIMIT 1
            "#
        )
        .fetch_optional(&self.pool)
        .await?;

        if let Some(row) = row {
            let config_id: String = row.get("id");
            Ok(Some(Configuration {
                id: config_id.clone(),
                name: row.get("name"),
                provider: row.get("provider"),
                model: row.get("model"),
                endpoint: row.get("endpoint"),
                is_active: true,
                created_at: DateTime::parse_from_rfc3339(row.get("created_at"))
                    .with_context(|| format!("Failed to parse created_at for config {}", config_id))?
                    .with_timezone(&Utc),
                updated_at: DateTime::parse_from_rfc3339(row.get("updated_at"))
                    .with_context(|| format!("Failed to parse updated_at for config {}", config_id))?
                    .with_timezone(&Utc),
            }))
        } else {
            Ok(None)
        }
    }

    /// 设置激活配置（同时取消其他配置的激活状态）
    pub async fn set_active_configuration(&self, config_id: &str) -> Result<()> {
        // 先取消所有激活
        sqlx::query("UPDATE configurations SET is_active = 0")
            .execute(&self.pool)
            .await?;

        // 激活指定配置
        sqlx::query(
            r#"
            UPDATE configurations
            SET is_active = 1, updated_at = ?
            WHERE id = ?
            "#
        )
        .bind(Utc::now().to_rfc3339())
        .bind(config_id)
        .execute(&self.pool)
        .await?;

        Ok(())
    }

    /// 更新配置
    pub async fn update_configuration(
        &self,
        config_id: &str,
        name: Option<&str>,
        model: Option<&str>,
        endpoint: Option<Option<&str>>,
    ) -> Result<()> {
        if let Some(name) = name {
            sqlx::query("UPDATE configurations SET name = ?, updated_at = ? WHERE id = ?")
                .bind(name)
                .bind(Utc::now().to_rfc3339())
                .bind(config_id)
                .execute(&self.pool)
                .await?;
        }

        if let Some(model) = model {
            sqlx::query("UPDATE configurations SET model = ?, updated_at = ? WHERE id = ?")
                .bind(model)
                .bind(Utc::now().to_rfc3339())
                .bind(config_id)
                .execute(&self.pool)
                .await?;
        }

        if let Some(endpoint) = endpoint {
            sqlx::query("UPDATE configurations SET endpoint = ?, updated_at = ? WHERE id = ?")
                .bind(endpoint)
                .bind(Utc::now().to_rfc3339())
                .bind(config_id)
                .execute(&self.pool)
                .await?;
        }

        Ok(())
    }

    /// 删除配置
    pub async fn delete_configuration(&self, config_id: &str) -> Result<()> {
        sqlx::query("DELETE FROM configurations WHERE id = ?")
            .bind(config_id)
            .execute(&self.pool)
            .await?;

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    async fn create_test_storage() -> Storage {
        Storage::new("sqlite::memory:").await.unwrap()
    }

    #[tokio::test]
    async fn test_session_lifecycle() {
        let storage = create_test_storage().await;

        // 创建会话
        let session = storage.create_session("Test Session").await.unwrap();
        assert_eq!(session.title, "Test Session");

        // 获取会话
        let retrieved = storage.get_session(&session.id).await.unwrap();
        assert!(retrieved.is_some());
        assert_eq!(retrieved.unwrap().title, "Test Session");

        // 更新标题
        storage.update_session_title(&session.id, "Updated Title").await.unwrap();
        let updated = storage.get_session(&session.id).await.unwrap().unwrap();
        assert_eq!(updated.title, "Updated Title");

        // 列出会话
        let sessions = storage.list_sessions().await.unwrap();
        assert_eq!(sessions.len(), 1);

        // 删除会话
        storage.delete_session(&session.id).await.unwrap();
        let deleted = storage.get_session(&session.id).await.unwrap();
        assert!(deleted.is_none());
    }

    #[tokio::test]
    async fn test_configuration_lifecycle() {
        let storage = create_test_storage().await;

        // 创建配置
        let config = storage
            .create_configuration("Claude Sonnet", "claude", "claude-3-5-sonnet-20241022", None)
            .await
            .unwrap();
        assert_eq!(config.provider, "claude");
        assert!(!config.is_active);

        // 列出配置
        let configs = storage.list_configurations().await.unwrap();
        assert_eq!(configs.len(), 1);

        // 设置激活
        storage.set_active_configuration(&config.id).await.unwrap();
        let active = storage.get_active_configuration().await.unwrap();
        assert!(active.is_some());
        assert_eq!(active.unwrap().id, config.id);

        // 更新配置
        storage
            .update_configuration(&config.id, Some("Updated Name"), None, None)
            .await
            .unwrap();
        let updated = storage.get_configuration(&config.id).await.unwrap().unwrap();
        assert_eq!(updated.name, "Updated Name");

        // 删除配置
        storage.delete_configuration(&config.id).await.unwrap();
        let configs = storage.list_configurations().await.unwrap();
        assert_eq!(configs.len(), 0);
    }

    #[tokio::test]
    async fn test_messages() {
        let storage = create_test_storage().await;

        // 创建会话
        let session = storage.create_session("Test").await.unwrap();

        // 保存消息
        let msg = Message::new_user("Hello");
        storage.save_message(&session.id, &msg).await.unwrap();

        // 获取消息
        let messages = storage.get_messages(&session.id).await.unwrap();
        assert_eq!(messages.len(), 1);
        assert_eq!(messages[0].content, "Hello");

        // 清空消息
        storage.clear_messages(&session.id).await.unwrap();
        let messages = storage.get_messages(&session.id).await.unwrap();
        assert_eq!(messages.len(), 0);
    }
}
