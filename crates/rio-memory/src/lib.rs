use anyhow::{Context, Result};

mod decisions;
mod evidence;
mod lessons;

pub use decisions::{Decision, DecisionStore};
pub use evidence::{Evidence, EvidenceStore};
pub use lessons::{Lesson, LessonsStore};

/// 共享内存管理器（统一接口）
pub struct SharedMemory {
    /// 事实存储
    pub evidence: EvidenceStore,
    /// 经验存储
    pub lessons: LessonsStore,
    /// 决策存储
    pub decisions: DecisionStore,
}

impl SharedMemory {
    /// 创建新的共享内存实例
    pub async fn new(database_url: &str) -> Result<Self> {
        let evidence = EvidenceStore::new(database_url)
            .await
            .context("Failed to initialize evidence store")?;

        let lessons = LessonsStore::new(database_url)
            .await
            .context("Failed to initialize lessons store")?;

        let decisions = DecisionStore::new(database_url)
            .await
            .context("Failed to initialize decisions store")?;

        Ok(Self {
            evidence,
            lessons,
            decisions,
        })
    }

    /// 创建内存实例（使用默认路径）
    pub async fn with_default_path(project_dir: &str) -> Result<Self> {
        let db_path = format!("{}/memory.db", project_dir);
        Self::new(&format!("sqlite:{}", db_path)).await
    }

    /// 创建测试用内存实例（内存数据库）
    pub async fn in_memory() -> Result<Self> {
        Self::new("sqlite::memory:").await
    }

    /// 清空所有存储
    pub async fn clear_all(&self) -> Result<()> {
        self.evidence.clear_all().await?;
        self.lessons.clear_all().await?;
        self.decisions.clear_all().await?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_shared_memory_creation() {
        let memory = SharedMemory::in_memory().await.unwrap();

        // 验证三个存储都已初始化
        assert_eq!(memory.evidence.list_all().await.unwrap().len(), 0);
        assert_eq!(memory.lessons.list_all().await.unwrap().len(), 0);
        assert_eq!(memory.decisions.list_all().await.unwrap().len(), 0);
    }

    #[tokio::test]
    async fn test_evidence_workflow() {
        let memory = SharedMemory::in_memory().await.unwrap();

        let evidence = Evidence::new("project.name", "rio-agent", "agent1", 0.95);
        memory.evidence.store(&evidence).await.unwrap();

        let results = memory.evidence.get_by_key("project.name").await.unwrap();
        assert_eq!(results.len(), 1);
        assert_eq!(results[0].value, "rio-agent");
    }

    #[tokio::test]
    async fn test_lessons_workflow() {
        let memory = SharedMemory::in_memory().await.unwrap();

        let lesson = Lesson::new(
            "Refactoring code",
            "Split large function",
            "Better maintainability",
            "Always break down complexity",
            vec!["refactoring".to_string()],
            "agent1",
        );
        memory.lessons.store(&lesson).await.unwrap();

        let results = memory
            .lessons
            .search_by_tags(&["refactoring".to_string()])
            .await
            .unwrap();
        assert_eq!(results.len(), 1);
    }

    #[tokio::test]
    async fn test_decisions_workflow() {
        let memory = SharedMemory::in_memory().await.unwrap();

        let decision = Decision::new(
            "Use SQLite for storage",
            "Simple and reliable",
            vec!["agent1".to_string()],
            vec!["PostgreSQL".to_string(), "MongoDB".to_string()],
        );
        memory.decisions.store(&decision).await.unwrap();

        let results = memory.decisions.list_all().await.unwrap();
        assert_eq!(results.len(), 1);
        assert_eq!(results[0].decision, "Use SQLite for storage");
    }

    #[tokio::test]
    async fn test_clear_all() {
        let memory = SharedMemory::in_memory().await.unwrap();

        // 存储数据
        let evidence = Evidence::new("key", "value", "agent1", 0.9);
        memory.evidence.store(&evidence).await.unwrap();

        let lesson = Lesson::new("ctx", "act", "out", "lesson", vec![], "agent1");
        memory.lessons.store(&lesson).await.unwrap();

        let decision = Decision::new("dec", "rat", vec![], vec![]);
        memory.decisions.store(&decision).await.unwrap();

        // 清空
        memory.clear_all().await.unwrap();

        // 验证
        assert_eq!(memory.evidence.list_all().await.unwrap().len(), 0);
        assert_eq!(memory.lessons.list_all().await.unwrap().len(), 0);
        assert_eq!(memory.decisions.list_all().await.unwrap().len(), 0);
    }

    #[tokio::test]
    async fn test_cross_store_operations() {
        let memory = SharedMemory::in_memory().await.unwrap();

        // 模拟多 Agent 协作场景
        let evidence = Evidence::new("task.status", "in_progress", "architect", 0.9);
        memory.evidence.store(&evidence).await.unwrap();

        let lesson = Lesson::new(
            "Planning complex task",
            "Break into subtasks",
            "Better coordination",
            "Always decompose first",
            vec!["planning".to_string()],
            "architect",
        );
        memory.lessons.store(&lesson).await.unwrap();

        let decision = Decision::new(
            "Use DAG for task execution",
            "Handles dependencies well",
            vec!["architect".to_string(), "reviewer".to_string()],
            vec!["Sequential".to_string(), "Parallel".to_string()],
        );
        memory.decisions.store(&decision).await.unwrap();

        // 验证所有数据都已存储
        assert_eq!(memory.evidence.list_all().await.unwrap().len(), 1);
        assert_eq!(memory.lessons.list_all().await.unwrap().len(), 1);
        assert_eq!(memory.decisions.list_all().await.unwrap().len(), 1);
    }
}
