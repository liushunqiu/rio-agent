use anyhow::{Context, Result};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::{Row, SqlitePool};
use uuid::Uuid;

/// 共享事实条目
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Evidence {
    /// 唯一 ID
    pub id: String,
    /// 事实键（命名空间式，如 "project.build_tool"）
    pub key: String,
    /// 事实值
    pub value: String,
    /// 来源 Agent ID
    pub source: String,
    /// 置信度（0.0 - 1.0）
    pub confidence: f64,
    /// 创建时间
    pub created_at: DateTime<Utc>,
    /// 最后更新时间
    pub updated_at: DateTime<Utc>,
}

impl Evidence {
    /// 创建新事实
    pub fn new(
        key: impl Into<String>,
        value: impl Into<String>,
        source: impl Into<String>,
        confidence: f64,
    ) -> Self {
        let now = Utc::now();
        Self {
            id: Uuid::new_v4().to_string(),
            key: key.into(),
            value: value.into(),
            source: source.into(),
            confidence: confidence.clamp(0.0, 1.0),
            created_at: now,
            updated_at: now,
        }
    }
}

/// Evidence Store - 共享事实库
pub struct EvidenceStore {
    pool: SqlitePool,
}

impl EvidenceStore {
    /// 创建新的 Evidence Store
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
            CREATE TABLE IF NOT EXISTS evidence (
                id TEXT PRIMARY KEY,
                key TEXT NOT NULL,
                value TEXT NOT NULL,
                source TEXT NOT NULL,
                confidence REAL NOT NULL CHECK(confidence >= 0.0 AND confidence <= 1.0),
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_evidence_key ON evidence(key);
            CREATE INDEX IF NOT EXISTS idx_evidence_source ON evidence(source);
            CREATE INDEX IF NOT EXISTS idx_evidence_confidence ON evidence(confidence);
            "#,
        )
        .execute(&self.pool)
        .await
        .context("Failed to create evidence table")?;

        Ok(())
    }

    /// 存储事实
    pub async fn store(&self, evidence: &Evidence) -> Result<()> {
        sqlx::query(
            r#"
            INSERT INTO evidence (id, key, value, source, confidence, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            "#,
        )
        .bind(&evidence.id)
        .bind(&evidence.key)
        .bind(&evidence.value)
        .bind(&evidence.source)
        .bind(evidence.confidence)
        .bind(evidence.created_at.to_rfc3339())
        .bind(evidence.updated_at.to_rfc3339())
        .execute(&self.pool)
        .await
        .context("Failed to store evidence")?;

        Ok(())
    }

    /// 更新事实（如果存在则更新，否则插入）
    pub async fn upsert(&self, evidence: &Evidence) -> Result<()> {
        sqlx::query(
            r#"
            INSERT INTO evidence (id, key, value, source, confidence, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                value = excluded.value,
                source = excluded.source,
                confidence = excluded.confidence,
                updated_at = excluded.updated_at
            "#,
        )
        .bind(&evidence.id)
        .bind(&evidence.key)
        .bind(&evidence.value)
        .bind(&evidence.source)
        .bind(evidence.confidence)
        .bind(evidence.created_at.to_rfc3339())
        .bind(evidence.updated_at.to_rfc3339())
        .execute(&self.pool)
        .await
        .context("Failed to upsert evidence")?;

        Ok(())
    }

    /// 根据键查询事实
    pub async fn get_by_key(&self, key: &str) -> Result<Vec<Evidence>> {
        let rows = sqlx::query("SELECT * FROM evidence WHERE key = ? ORDER BY confidence DESC")
            .bind(key)
            .fetch_all(&self.pool)
            .await
            .context("Failed to query evidence by key")?;

        rows.into_iter().map(|row| self.row_to_evidence(&row)).collect()
    }

    /// 根据 ID 查询事实
    pub async fn get_by_id(&self, id: &str) -> Result<Option<Evidence>> {
        let row = sqlx::query("SELECT * FROM evidence WHERE id = ?")
            .bind(id)
            .fetch_optional(&self.pool)
            .await
            .context("Failed to query evidence by id")?;

        row.map(|r| self.row_to_evidence(&r)).transpose()
    }

    /// 查询所有事实（按置信度排序）
    pub async fn list_all(&self) -> Result<Vec<Evidence>> {
        let rows = sqlx::query("SELECT * FROM evidence ORDER BY confidence DESC, created_at DESC")
            .fetch_all(&self.pool)
            .await
            .context("Failed to list all evidence")?;

        rows.into_iter().map(|row| self.row_to_evidence(&row)).collect()
    }

    /// 根据来源查询事实
    pub async fn get_by_source(&self, source: &str) -> Result<Vec<Evidence>> {
        let rows = sqlx::query("SELECT * FROM evidence WHERE source = ? ORDER BY created_at DESC")
            .bind(source)
            .fetch_all(&self.pool)
            .await
            .context("Failed to query evidence by source")?;

        rows.into_iter().map(|row| self.row_to_evidence(&row)).collect()
    }

    /// 删除事实
    pub async fn delete(&self, id: &str) -> Result<bool> {
        let result = sqlx::query("DELETE FROM evidence WHERE id = ?")
            .bind(id)
            .execute(&self.pool)
            .await
            .context("Failed to delete evidence")?;

        Ok(result.rows_affected() > 0)
    }

    /// 清空所有事实
    pub async fn clear_all(&self) -> Result<()> {
        sqlx::query("DELETE FROM evidence")
            .execute(&self.pool)
            .await
            .context("Failed to clear all evidence")?;

        Ok(())
    }

    /// 将数据库行转换为 Evidence
    fn row_to_evidence(&self, row: &sqlx::sqlite::SqliteRow) -> Result<Evidence> {
        let id: String = row.get("id");
        let created_at_str: String = row.get("created_at");
        let updated_at_str: String = row.get("updated_at");

        Ok(Evidence {
            id: id.clone(),
            key: row.get("key"),
            value: row.get("value"),
            source: row.get("source"),
            confidence: row.get("confidence"),
            created_at: DateTime::parse_from_rfc3339(&created_at_str)
                .with_context(|| format!("Failed to parse created_at for evidence {}", id))?
                .with_timezone(&Utc),
            updated_at: DateTime::parse_from_rfc3339(&updated_at_str)
                .with_context(|| format!("Failed to parse updated_at for evidence {}", id))?
                .with_timezone(&Utc),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    async fn create_test_store() -> EvidenceStore {
        EvidenceStore::new("sqlite::memory:")
            .await
            .expect("Failed to create test store")
    }

    #[tokio::test]
    async fn test_store_and_get() {
        let store = create_test_store().await;
        let evidence = Evidence::new("test.key", "test_value", "agent1", 0.9);

        store.store(&evidence).await.unwrap();

        let results = store.get_by_key("test.key").await.unwrap();
        assert_eq!(results.len(), 1);
        assert_eq!(results[0].value, "test_value");
        assert_eq!(results[0].confidence, 0.9);
    }

    #[tokio::test]
    async fn test_upsert() {
        let store = create_test_store().await;
        let mut evidence = Evidence::new("test.key", "original", "agent1", 0.8);

        store.upsert(&evidence).await.unwrap();

        // 更新
        evidence.value = "updated".to_string();
        evidence.confidence = 0.95;
        evidence.updated_at = Utc::now();

        store.upsert(&evidence).await.unwrap();

        let results = store.get_by_key("test.key").await.unwrap();
        assert_eq!(results.len(), 1);
        assert_eq!(results[0].value, "updated");
        assert_eq!(results[0].confidence, 0.95);
    }

    #[tokio::test]
    async fn test_get_by_source() {
        let store = create_test_store().await;

        let e1 = Evidence::new("key1", "value1", "agent1", 0.9);
        let e2 = Evidence::new("key2", "value2", "agent1", 0.8);
        let e3 = Evidence::new("key3", "value3", "agent2", 0.7);

        store.store(&e1).await.unwrap();
        store.store(&e2).await.unwrap();
        store.store(&e3).await.unwrap();

        let results = store.get_by_source("agent1").await.unwrap();
        assert_eq!(results.len(), 2);
    }

    #[tokio::test]
    async fn test_list_all_sorted_by_confidence() {
        let store = create_test_store().await;

        let e1 = Evidence::new("key1", "value1", "agent1", 0.5);
        let e2 = Evidence::new("key2", "value2", "agent2", 0.9);
        let e3 = Evidence::new("key3", "value3", "agent3", 0.7);

        store.store(&e1).await.unwrap();
        store.store(&e2).await.unwrap();
        store.store(&e3).await.unwrap();

        let results = store.list_all().await.unwrap();
        assert_eq!(results.len(), 3);
        assert_eq!(results[0].confidence, 0.9);
        assert_eq!(results[1].confidence, 0.7);
        assert_eq!(results[2].confidence, 0.5);
    }

    #[tokio::test]
    async fn test_delete() {
        let store = create_test_store().await;
        let evidence = Evidence::new("test.key", "test_value", "agent1", 0.9);

        store.store(&evidence).await.unwrap();
        let deleted = store.delete(&evidence.id).await.unwrap();
        assert!(deleted);

        let result = store.get_by_id(&evidence.id).await.unwrap();
        assert!(result.is_none());
    }

    #[tokio::test]
    async fn test_confidence_clamping() {
        let e1 = Evidence::new("key", "value", "agent", 1.5);
        assert_eq!(e1.confidence, 1.0);

        let e2 = Evidence::new("key", "value", "agent", -0.5);
        assert_eq!(e2.confidence, 0.0);
    }

    #[tokio::test]
    async fn test_clear_all() {
        let store = create_test_store().await;

        let e1 = Evidence::new("key1", "value1", "agent1", 0.9);
        let e2 = Evidence::new("key2", "value2", "agent2", 0.8);

        store.store(&e1).await.unwrap();
        store.store(&e2).await.unwrap();

        store.clear_all().await.unwrap();

        let results = store.list_all().await.unwrap();
        assert_eq!(results.len(), 0);
    }
}
