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
}
