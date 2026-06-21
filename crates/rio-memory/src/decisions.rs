use anyhow::{Context, Result};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::{Row, SqlitePool};
use uuid::Uuid;

/// 决策条目
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Decision {
    /// 唯一 ID
    pub id: String,
    /// 决策内容
    pub decision: String,
    /// 决策理由
    pub rationale: String,
    /// 参与者（Agent IDs，逗号分隔）
    pub participants: Vec<String>,
    /// 考虑的选项（JSON 数组）
    pub alternatives: Vec<String>,
    /// 创建时间
    pub created_at: DateTime<Utc>,
}

impl Decision {
    /// 创建新决策
    pub fn new(
        decision: impl Into<String>,
        rationale: impl Into<String>,
        participants: Vec<String>,
        alternatives: Vec<String>,
    ) -> Self {
        Self {
            id: Uuid::new_v4().to_string(),
            decision: decision.into(),
            rationale: rationale.into(),
            participants,
            alternatives,
            created_at: Utc::now(),
        }
    }
}

/// Decision Log Store - 决策日志库
pub struct DecisionStore {
    pool: SqlitePool,
}

impl DecisionStore {
    /// 创建新的 Decision Store
    pub async fn new(database_url: &str) -> Result<Self> {
        let pool = SqlitePool::connect(database_url)
            .await
            .context("Failed to connect to database")?;

        let store = Self { pool };
        store.init_schema().await?;
        Ok(store)
    }

    /// 初始化数据库 Schema
    async fn init_schema(&self) -> Result<()> {
        sqlx::query(
            r#"
            CREATE TABLE IF NOT EXISTS decisions (
                id TEXT PRIMARY KEY,
                decision TEXT NOT NULL,
                rationale TEXT NOT NULL,
                participants TEXT NOT NULL,
                alternatives TEXT NOT NULL,
                created_at TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_decisions_created_at ON decisions(created_at);
            "#,
        )
        .execute(&self.pool)
        .await
        .context("Failed to create decisions table")?;

        Ok(())
    }

    /// 存储决策
    pub async fn store(&self, decision: &Decision) -> Result<()> {
        let participants_str = decision.participants.join(",");
        let alternatives_json = serde_json::to_string(&decision.alternatives)
            .context("Failed to serialize alternatives")?;

        sqlx::query(
            r#"
            INSERT INTO decisions (id, decision, rationale, participants, alternatives, created_at)
            VALUES (?, ?, ?, ?, ?, ?)
            "#,
        )
        .bind(&decision.id)
        .bind(&decision.decision)
        .bind(&decision.rationale)
        .bind(&participants_str)
        .bind(&alternatives_json)
        .bind(decision.created_at.to_rfc3339())
        .execute(&self.pool)
        .await
        .context("Failed to store decision")?;

        Ok(())
    }

    /// 根据 ID 查询决策
    pub async fn get_by_id(&self, id: &str) -> Result<Option<Decision>> {
        let row = sqlx::query("SELECT * FROM decisions WHERE id = ?")
            .bind(id)
            .fetch_optional(&self.pool)
            .await
            .context("Failed to query decision by id")?;

        row.map(|r| self.row_to_decision(&r)).transpose()
    }

    /// 根据参与者查询决策
    pub async fn get_by_participant(&self, participant: &str) -> Result<Vec<Decision>> {
        let rows = sqlx::query(
            "SELECT * FROM decisions WHERE participants LIKE ? ORDER BY created_at DESC",
        )
        .bind(format!("%{}%", participant))
        .fetch_all(&self.pool)
        .await
        .context("Failed to query decisions by participant")?;

        rows.into_iter()
            .map(|row| self.row_to_decision(&row))
            .collect()
    }

    /// 列出最近的决策（限制数量）
    pub async fn list_recent(&self, limit: i64) -> Result<Vec<Decision>> {
        let rows = sqlx::query("SELECT * FROM decisions ORDER BY created_at DESC LIMIT ?")
            .bind(limit)
            .fetch_all(&self.pool)
            .await
            .context("Failed to list recent decisions")?;

        rows.into_iter()
            .map(|row| self.row_to_decision(&row))
            .collect()
    }

    /// 列出所有决策
    pub async fn list_all(&self) -> Result<Vec<Decision>> {
        let rows = sqlx::query("SELECT * FROM decisions ORDER BY created_at DESC")
            .fetch_all(&self.pool)
            .await
            .context("Failed to list all decisions")?;

        rows.into_iter()
            .map(|row| self.row_to_decision(&row))
            .collect()
    }

    /// 删除决策
    pub async fn delete(&self, id: &str) -> Result<bool> {
        let result = sqlx::query("DELETE FROM decisions WHERE id = ?")
            .bind(id)
            .execute(&self.pool)
            .await
            .context("Failed to delete decision")?;

        Ok(result.rows_affected() > 0)
    }

    /// 清空所有决策
    pub async fn clear_all(&self) -> Result<()> {
        sqlx::query("DELETE FROM decisions")
            .execute(&self.pool)
            .await
            .context("Failed to clear all decisions")?;

        Ok(())
    }

    /// 将数据库行转换为 Decision
    fn row_to_decision(&self, row: &sqlx::sqlite::SqliteRow) -> Result<Decision> {
        let id: String = row.get("id");
        let created_at_str: String = row.get("created_at");
        let participants_str: String = row.get("participants");
        let alternatives_json: String = row.get("alternatives");

        let participants = if participants_str.is_empty() {
            Vec::new()
        } else {
            participants_str
                .split(',')
                .map(|s| s.to_string())
                .collect()
        };

        let alternatives: Vec<String> = serde_json::from_str(&alternatives_json)
            .with_context(|| format!("Failed to parse alternatives for decision {}", id))?;

        Ok(Decision {
            id: id.clone(),
            decision: row.get("decision"),
            rationale: row.get("rationale"),
            participants,
            alternatives,
            created_at: DateTime::parse_from_rfc3339(&created_at_str)
                .with_context(|| format!("Failed to parse created_at for decision {}", id))?
                .with_timezone(&Utc),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    async fn create_test_store() -> DecisionStore {
        DecisionStore::new("sqlite::memory:")
            .await
            .expect("Failed to create test store")
    }

    #[tokio::test]
    async fn test_store_and_get() {
        let store = create_test_store().await;
        let decision = Decision::new(
            "Use Rust for backend",
            "Performance and safety",
            vec!["agent1".to_string(), "agent2".to_string()],
            vec!["Go".to_string(), "Python".to_string()],
        );

        store.store(&decision).await.unwrap();

        let result = store.get_by_id(&decision.id).await.unwrap();
        assert!(result.is_some());
        let d = result.unwrap();
        assert_eq!(d.decision, "Use Rust for backend");
        assert_eq!(d.participants.len(), 2);
        assert_eq!(d.alternatives.len(), 2);
    }

    #[tokio::test]
    async fn test_get_by_participant() {
        let store = create_test_store().await;

        let d1 = Decision::new(
            "Decision 1",
            "Reason 1",
            vec!["agent1".to_string()],
            vec![],
        );
        let d2 = Decision::new(
            "Decision 2",
            "Reason 2",
            vec!["agent1".to_string(), "agent2".to_string()],
            vec![],
        );
        let d3 = Decision::new(
            "Decision 3",
            "Reason 3",
            vec!["agent3".to_string()],
            vec![],
        );

        store.store(&d1).await.unwrap();
        store.store(&d2).await.unwrap();
        store.store(&d3).await.unwrap();

        let results = store.get_by_participant("agent1").await.unwrap();
        assert_eq!(results.len(), 2);
    }

    #[tokio::test]
    async fn test_list_recent() {
        let store = create_test_store().await;

        for i in 0..5 {
            let decision = Decision::new(
                format!("Decision {}", i),
                "Reason",
                vec![],
                vec![],
            );
            store.store(&decision).await.unwrap();
            tokio::time::sleep(tokio::time::Duration::from_millis(10)).await;
        }

        let results = store.list_recent(3).await.unwrap();
        assert_eq!(results.len(), 3);
        assert_eq!(results[0].decision, "Decision 4");
        assert_eq!(results[2].decision, "Decision 2");
    }

    #[tokio::test]
    async fn test_delete() {
        let store = create_test_store().await;
        let decision = Decision::new("Decision", "Reason", vec![], vec![]);

        store.store(&decision).await.unwrap();
        let deleted = store.delete(&decision.id).await.unwrap();
        assert!(deleted);

        let result = store.get_by_id(&decision.id).await.unwrap();
        assert!(result.is_none());
    }

    #[tokio::test]
    async fn test_empty_alternatives() {
        let store = create_test_store().await;
        let decision = Decision::new("Decision", "Reason", vec!["agent1".to_string()], vec![]);

        store.store(&decision).await.unwrap();

        let result = store.get_by_id(&decision.id).await.unwrap().unwrap();
        assert_eq!(result.alternatives.len(), 0);
    }

    #[tokio::test]
    async fn test_clear_all() {
        let store = create_test_store().await;

        let d1 = Decision::new("Decision 1", "Reason 1", vec![], vec![]);
        let d2 = Decision::new("Decision 2", "Reason 2", vec![], vec![]);

        store.store(&d1).await.unwrap();
        store.store(&d2).await.unwrap();

        store.clear_all().await.unwrap();

        let results = store.list_all().await.unwrap();
        assert_eq!(results.len(), 0);
    }
}
