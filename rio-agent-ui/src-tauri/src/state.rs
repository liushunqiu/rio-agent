use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;
use anyhow::Result;

use rio_core::{AgentEngine, ToolRegistry, AIProvider};
use rio_storage::Storage;
use rio_providers::ClaudeProvider;

pub struct AppState {
    pub storage: Arc<Storage>,
    pub tool_registry: Arc<ToolRegistry>,
    pub engines: Arc<RwLock<HashMap<String, Arc<AgentEngine>>>>,
}

impl AppState {
    pub async fn new() -> Result<Self> {
        // 初始化存储
        let storage = Arc::new(
            Storage::new("sqlite:./rio_agent.db")
                .await?
        );

        // 初始化工具注册表
        let mut tool_registry = ToolRegistry::new();
        rio_tools::register_default_tools(&mut tool_registry);
        let tool_registry = Arc::new(tool_registry);

        // 初始化引擎映射
        let engines = Arc::new(RwLock::new(HashMap::new()));

        Ok(Self {
            storage,
            tool_registry,
            engines,
        })
    }

    /// 获取或创建对话的 AgentEngine
    pub async fn get_or_create_engine(
        &self,
        conversation_id: &str,
    ) -> Result<Arc<AgentEngine>> {
        // 先尝试从缓存获取
        {
            let engines = self.engines.read().await;
            if let Some(engine) = engines.get(conversation_id) {
                return Ok(engine.clone());
            }
        }

        // 创建新引擎（暂时硬编码使用 Claude）
        // TODO: 从配置中读取
        let provider = self.create_default_provider()?;
        let engine = Arc::new(AgentEngine::new(
            provider,
            self.tool_registry.clone(),
        ));

        // 缓存引擎
        let mut engines = self.engines.write().await;
        engines.insert(conversation_id.to_string(), engine.clone());

        Ok(engine)
    }

    /// 创建默认 AI Provider
    /// TODO: 从数据库配置中读取
    fn create_default_provider(&self) -> Result<Arc<dyn AIProvider>> {
        // 暂时返回 Claude Provider
        // 实际使用时需要从环境变量或配置文件读取 API Key
        let api_key = std::env::var("ANTHROPIC_API_KEY")
            .unwrap_or_else(|_| String::new());

        Ok(Arc::new(ClaudeProvider::new(
            api_key,
            "claude-3-5-sonnet-20241022".to_string(),
        )))
    }

    /// 移除引擎缓存
    pub async fn remove_engine(&self, conversation_id: &str) {
        let mut engines = self.engines.write().await;
        engines.remove(conversation_id);
    }
}
