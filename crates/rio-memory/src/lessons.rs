use anyhow::{Context, Result};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::{Row, SqlitePool};
use uuid::Uuid;

/// 经验教训条目
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Lesson {
    /// 唯一 ID
    pub id: String,
    /// 情境描述
    pub context: String,
    /// 采取的行动
    pub action: String,
    /// 行动结果
    pub outcome: String,
    /// 学到的教训
    pub lesson: String,
    /// 标签（用于检索，逗号分隔）
    pub tags: Vec<String>,
    /// 记录者 Agent ID
    pub recorder: String,
    /// 创建时间
    pub created_at: DateTime<Utc>,
}

impl Lesson {
    /// 创建新经验
    pub fn new(
        context: impl Into<String>,
        action: impl Into<String>,
        outcome: impl Into<String>,
        lesson: impl Into<String>,
        tags: Vec<String>,
        recorder: impl Into<String>,
    ) -> Self {
        Self {
            id: Uuid::new_v4().to_string(),
            context: context.into(),
            action: action.into(),
            outcome: outcome.into(),
            lesson: lesson.into(),
            tags,
            recorder: recorder.into(),
            created_at: Utc::now(),
        }
    }
}

/// Lessons Learned Store - 经验学习库
pub struct LessonsStore {
    pool: SqlitePool,
}

impl LessonsStore {
    /// 创建新的 Lessons Store
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
            CREATE TABLE IF NOT EXISTS lessons (
                id TEXT PRIMARY KEY,
                context TEXT NOT NULL,
                action TEXT NOT NULL,
                outcome TEXT NOT NULL,
                lesson TEXT NOT NULL,
                tags TEXT NOT NULL,
                recorder TEXT NOT NULL,
                created_at TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_lessons_recorder ON lessons(recorder);
            CREATE INDEX IF NOT EXISTS idx_lessons_created_at ON lessons(created_at);
            "#,
        )
        .execute(&self.pool)
        .await
        .context("Failed to create lessons table")?;

        Ok(())
    }

    /// 存储经验
    pub async fn store(&self, lesson: &Lesson) -> Result<()> {
        let tags_str = lesson.tags.join(",");

        sqlx::query(
            r#"
            INSERT INTO lessons (id, context, action, outcome, lesson, tags, recorder, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            "#,
        )
        .bind(&lesson.id)
        .bind(&lesson.context)
        .bind(&lesson.action)
        .bind(&lesson.outcome)
        .bind(&lesson.lesson)
        .bind(&tags_str)
        .bind(&lesson.recorder)
        .bind(lesson.created_at.to_rfc3339())
        .execute(&self.pool)
        .await
        .context("Failed to store lesson")?;

        Ok(())
    }

    /// 根据 ID 查询经验
    pub async fn get_by_id(&self, id: &str) -> Result<Option<Lesson>> {
        let row = sqlx::query("SELECT * FROM lessons WHERE id = ?")
            .bind(id)
            .fetch_optional(&self.pool)
            .await
            .context("Failed to query lesson by id")?;

        row.map(|r| self.row_to_lesson(&r)).transpose()
    }

    /// 根据标签查询经验（支持多标签匹配）
    pub async fn search_by_tags(&self, tags: &[String]) -> Result<Vec<Lesson>> {
        let mut query = "SELECT * FROM lessons WHERE ".to_string();
        let conditions: Vec<String> = tags
            .iter()
            .map(|_| "tags LIKE ?".to_string())
            .collect();
        query.push_str(&conditions.join(" OR "));
        query.push_str(" ORDER BY created_at DESC");

        let mut sql_query = sqlx::query(&query);
        for tag in tags {
            sql_query = sql_query.bind(format!("%{}%", tag));
        }

        let rows = sql_query
            .fetch_all(&self.pool)
            .await
            .context("Failed to search lessons by tags")?;

        rows.into_iter().map(|row| self.row_to_lesson(&row)).collect()
    }

    /// 根据记录者查询经验
    pub async fn get_by_recorder(&self, recorder: &str) -> Result<Vec<Lesson>> {
        let rows = sqlx::query("SELECT * FROM lessons WHERE recorder = ? ORDER BY created_at DESC")
            .bind(recorder)
            .fetch_all(&self.pool)
            .await
            .context("Failed to query lessons by recorder")?;

        rows.into_iter().map(|row| self.row_to_lesson(&row)).collect()
    }

    /// 列出最近的经验（限制数量）
    pub async fn list_recent(&self, limit: i64) -> Result<Vec<Lesson>> {
        let rows = sqlx::query("SELECT * FROM lessons ORDER BY created_at DESC LIMIT ?")
            .bind(limit)
            .fetch_all(&self.pool)
            .await
            .context("Failed to list recent lessons")?;

        rows.into_iter().map(|row| self.row_to_lesson(&row)).collect()
    }

    /// 列出所有经验
    pub async fn list_all(&self) -> Result<Vec<Lesson>> {
        let rows = sqlx::query("SELECT * FROM lessons ORDER BY created_at DESC")
            .fetch_all(&self.pool)
            .await
            .context("Failed to list all lessons")?;

        rows.into_iter().map(|row| self.row_to_lesson(&row)).collect()
    }

    /// 删除经验
    pub async fn delete(&self, id: &str) -> Result<bool> {
        let result = sqlx::query("DELETE FROM lessons WHERE id = ?")
            .bind(id)
            .execute(&self.pool)
            .await
            .context("Failed to delete lesson")?;

        Ok(result.rows_affected() > 0)
    }

    /// 清空所有经验
    pub async fn clear_all(&self) -> Result<()> {
        sqlx::query("DELETE FROM lessons")
            .execute(&self.pool)
            .await
            .context("Failed to clear all lessons")?;

        Ok(())
    }

    /// 将数据库行转换为 Lesson
    fn row_to_lesson(&self, row: &sqlx::sqlite::SqliteRow) -> Result<Lesson> {
        let id: String = row.get("id");
        let created_at_str: String = row.get("created_at");
        let tags_str: String = row.get("tags");

        let tags = if tags_str.is_empty() {
            Vec::new()
        } else {
            tags_str.split(',').map(|s| s.to_string()).collect()
        };

        Ok(Lesson {
            id: id.clone(),
            context: row.get("context"),
            action: row.get("action"),
            outcome: row.get("outcome"),
            lesson: row.get("lesson"),
            tags,
            recorder: row.get("recorder"),
            created_at: DateTime::parse_from_rfc3339(&created_at_str)
                .with_context(|| format!("Failed to parse created_at for lesson {}", id))?
                .with_timezone(&Utc),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    async fn create_test_store() -> LessonsStore {
        LessonsStore::new("sqlite::memory:")
            .await
            .expect("Failed to create test store")
    }

    #[tokio::test]
    async fn test_store_and_get() {
        let store = create_test_store().await;
        let lesson = Lesson::new(
            "Refactoring large function",
            "Split into smaller functions",
            "Improved readability",
            "Always break down complex logic",
            vec!["refactoring".to_string(), "best-practices".to_string()],
            "agent1",
        );

        store.store(&lesson).await.unwrap();

        let result = store.get_by_id(&lesson.id).await.unwrap();
        assert!(result.is_some());
        assert_eq!(result.unwrap().lesson, "Always break down complex logic");
    }

    #[tokio::test]
    async fn test_search_by_tags() {
        let store = create_test_store().await;

        let l1 = Lesson::new(
            "ctx1",
            "act1",
            "out1",
            "lesson1",
            vec!["rust".to_string(), "performance".to_string()],
            "agent1",
        );
        let l2 = Lesson::new(
            "ctx2",
            "act2",
            "out2",
            "lesson2",
            vec!["rust".to_string(), "safety".to_string()],
            "agent2",
        );
        let l3 = Lesson::new(
            "ctx3",
            "act3",
            "out3",
            "lesson3",
            vec!["python".to_string()],
            "agent3",
        );

        store.store(&l1).await.unwrap();
        store.store(&l2).await.unwrap();
        store.store(&l3).await.unwrap();

        let results = store
            .search_by_tags(&["rust".to_string()])
            .await
            .unwrap();
        assert_eq!(results.len(), 2);
    }

    #[tokio::test]
    async fn test_get_by_recorder() {
        let store = create_test_store().await;

        let l1 = Lesson::new("ctx1", "act1", "out1", "lesson1", vec![], "agent1");
        let l2 = Lesson::new("ctx2", "act2", "out2", "lesson2", vec![], "agent1");
        let l3 = Lesson::new("ctx3", "act3", "out3", "lesson3", vec![], "agent2");

        store.store(&l1).await.unwrap();
        store.store(&l2).await.unwrap();
        store.store(&l3).await.unwrap();

        let results = store.get_by_recorder("agent1").await.unwrap();
        assert_eq!(results.len(), 2);
    }

    #[tokio::test]
    async fn test_list_recent() {
        let store = create_test_store().await;

        for i in 0..5 {
            let lesson = Lesson::new(
                format!("ctx{}", i),
                "action",
                "outcome",
                "lesson",
                vec![],
                "agent1",
            );
            store.store(&lesson).await.unwrap();
            tokio::time::sleep(tokio::time::Duration::from_millis(10)).await;
        }

        let results = store.list_recent(3).await.unwrap();
        assert_eq!(results.len(), 3);
        assert_eq!(results[0].context, "ctx4");
        assert_eq!(results[2].context, "ctx2");
    }

    #[tokio::test]
    async fn test_delete() {
        let store = create_test_store().await;
        let lesson = Lesson::new("ctx", "act", "out", "lesson", vec![], "agent1");

        store.store(&lesson).await.unwrap();
        let deleted = store.delete(&lesson.id).await.unwrap();
        assert!(deleted);

        let result = store.get_by_id(&lesson.id).await.unwrap();
        assert!(result.is_none());
    }

    #[tokio::test]
    async fn test_tags_empty() {
        let store = create_test_store().await;
        let lesson = Lesson::new("ctx", "act", "out", "lesson", vec![], "agent1");

        store.store(&lesson).await.unwrap();

        let result = store.get_by_id(&lesson.id).await.unwrap().unwrap();
        assert_eq!(result.tags.len(), 0);
    }

    #[tokio::test]
    async fn test_clear_all() {
        let store = create_test_store().await;

        let l1 = Lesson::new("ctx1", "act1", "out1", "lesson1", vec![], "agent1");
        let l2 = Lesson::new("ctx2", "act2", "out2", "lesson2", vec![], "agent2");

        store.store(&l1).await.unwrap();
        store.store(&l2).await.unwrap();

        store.clear_all().await.unwrap();

        let results = store.list_all().await.unwrap();
        assert_eq!(results.len(), 0);
    }
}
