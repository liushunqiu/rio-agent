use crate::mention::MentionTarget;
use anyhow::{anyhow, Result};
use chrono::{DateTime, Utc};
use rio_core::MultiAgentEngine;
use std::sync::Arc;
use tokio::sync::{mpsc, oneshot};
use uuid::Uuid;

/// A2A 消息（Agent-to-Agent）
#[derive(Debug, Clone)]
pub struct A2AMessage {
    /// 消息 ID
    pub id: Arc<str>,
    /// 发送方 Agent ID
    pub from: Arc<str>,
    /// 接收方 Agent ID（None 表示广播）
    pub to: Option<Arc<str>>,
    /// 消息内容
    pub content: Arc<str>,
    /// 调用链（用于死锁检测）
    pub call_chain: Arc<[Arc<str>]>,
    /// 创建时间
    pub created_at: DateTime<Utc>,
}

impl A2AMessage {
    /// 创建新消息
    pub fn new(
        from: impl Into<String>,
        to: Option<impl Into<String>>,
        content: impl Into<String>,
        call_chain: Vec<String>,
    ) -> Self {
        Self {
            id: Uuid::new_v4().to_string().into(),
            from: from.into().into(),
            to: to.map(|s| s.into().into()),
            content: content.into().into(),
            call_chain: call_chain.into_iter().map(|s| s.into()).collect(),
            created_at: Utc::now(),
        }
    }
}

/// 路由请求（带响应通道）
struct RouteRequest {
    message: Arc<A2AMessage>,
    response_tx: oneshot::Sender<Result<String>>,
}

/// 死锁预防器
struct DeadlockPrevention;

impl DeadlockPrevention {
    /// 检测调用链中是否有循环
    fn detect_cycle(call_chain: &[Arc<str>], target: &str) -> bool {
        call_chain.iter().any(|agent| agent.as_ref() == target)
    }
}

/// A2A 路由器
pub struct A2ARouter {
    /// 消息队列发送端
    tx: mpsc::Sender<RouteRequest>,
}

impl A2ARouter {
    /// 创建新的路由器
    pub fn new(engine: Arc<MultiAgentEngine>) -> Self {
        let (tx, rx) = mpsc::channel(100);

        // 启动后台处理循环
        tokio::spawn(Self::process_loop(rx, engine));

        Self { tx }
    }

    /// 路由消息到目标 Agent
    pub async fn route(
        &self,
        from: &str,
        target: MentionTarget,
        content: &str,
        call_chain: Vec<String>,
    ) -> Result<Vec<(String, String)>> {
        match target {
            MentionTarget::Single(agent_name) => {
                let response = self
                    .route_single(from, &agent_name, content, call_chain)
                    .await?;
                Ok(vec![(agent_name, response)])
            }
            MentionTarget::Multiple(agent_names) => {
                self.route_multiple(from, agent_names, content, call_chain)
                    .await
            }
            MentionTarget::Broadcast => {
                Err(anyhow!("Broadcast routing not yet implemented"))
            }
        }
    }

    /// 路由到单个 Agent
    async fn route_single(
        &self,
        from: &str,
        to: &str,
        content: &str,
        call_chain: Vec<String>,
    ) -> Result<String> {
        // 死锁检测
        if DeadlockPrevention::detect_cycle(&call_chain.iter().map(|s| s.as_str().into()).collect::<Vec<_>>(), to) {
            return Err(anyhow!(
                "Circular call detected: {} already in call chain",
                to
            ));
        }

        let message = Arc::new(A2AMessage::new(
            from.to_string(),
            Some(to.to_string()),
            content.to_string(),
            call_chain,
        ));

        let (response_tx, response_rx) = oneshot::channel();
        let request = RouteRequest {
            message,
            response_tx,
        };

        self.tx
            .send(request)
            .await
            .map_err(|_| anyhow!("Router channel closed"))?;

        // 等待响应（带超时）
        tokio::time::timeout(std::time::Duration::from_secs(30), response_rx)
            .await
            .map_err(|_| anyhow!("Agent {} response timeout", to))?
            .map_err(|_| anyhow!("Response channel closed"))?
    }

    /// 路由到多个 Agent（并发执行）
    async fn route_multiple(
        &self,
        from: &str,
        targets: Vec<String>,
        content: &str,
        call_chain: Vec<String>,
    ) -> Result<Vec<(String, String)>> {
        let mut tasks = Vec::new();

        for target in targets {
            let router = self.clone();
            let from = from.to_string();
            let content = content.to_string();
            let call_chain = call_chain.clone();

            let task = tokio::spawn(async move {
                let response = router
                    .route_single(&from, &target, &content, call_chain)
                    .await;
                (target, response)
            });

            tasks.push(task);
        }

        let mut results = Vec::new();
        for task in tasks {
            let (target, response) = task.await.map_err(|e| anyhow!("Task join error: {}", e))?;
            match response {
                Ok(content) => results.push((target, content)),
                Err(e) => {
                    // 单个 Agent 失败不影响其他 Agent
                    eprintln!("Agent {} failed: {}", target, e);
                }
            }
        }

        if results.is_empty() {
            Err(anyhow!("All agents failed to respond"))
        } else {
            Ok(results)
        }
    }

    /// 后台消息处理循环
    async fn process_loop(
        mut rx: mpsc::Receiver<RouteRequest>,
        engine: Arc<MultiAgentEngine>,
    ) {
        while let Some(request) = rx.recv().await {
            let engine = engine.clone();
            let message = request.message.clone();
            let response_tx = request.response_tx;

            // 每个消息独立处理（并发）
            tokio::spawn(async move {
                let result = Self::handle_message(&engine, &message).await;
                let _ = response_tx.send(result);
            });
        }
    }

    /// 处理单条消息
    async fn handle_message(
        engine: &MultiAgentEngine,
        message: &A2AMessage,
    ) -> Result<String> {
        let target_id = message
            .to
            .as_ref()
            .ok_or_else(|| anyhow!("Broadcast not supported"))?;

        // 查找目标 Agent
        let agent = engine
            .get_agent_by_name(target_id.as_ref())
            .ok_or_else(|| anyhow!("Agent {} not found", target_id))?;

        // 构建上下文（包含调用链信息）
        let context = vec![];

        // 执行 Agent
        engine
            .execute_agent(&agent.identity.id, message.content.as_ref(), context)
            .await
    }

    /// 克隆路由器（共享发送端）
    fn clone(&self) -> Self {
        Self {
            tx: self.tx.clone(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use rio_core::{ToolRegistry, AIProvider, StreamChunk, Message};
    use rio_identity::{AgentIdentity, AgentRole};
    use async_trait::async_trait;

    // Mock Provider
    struct MockProvider {
        response: String,
    }

    #[async_trait]
    impl AIProvider for MockProvider {
        async fn send_message(
            &self,
            _messages: &[Message],
            _tools: Option<Vec<serde_json::Value>>,
        ) -> Result<Message> {
            Ok(Message::new_assistant(&self.response))
        }

        async fn stream_message(
            &self,
            _messages: &[Message],
            _tools: Option<Vec<serde_json::Value>>,
        ) -> Result<mpsc::Receiver<Result<StreamChunk>>> {
            unimplemented!()
        }

        fn model_name(&self) -> &str {
            "mock"
        }
    }

    async fn create_test_router() -> (A2ARouter, Arc<MultiAgentEngine>) {
        let tools = Arc::new(ToolRegistry::new());
        let mut engine = MultiAgentEngine::new(tools);

        // 创建测试 Agent
        let identity1 = AgentIdentity::new(
            "opus",
            AgentRole::Architect,
            "Thoughtful",
            "anthropic",
            "claude-opus-4",
        );
        let identity2 = AgentIdentity::new(
            "codex",
            AgentRole::Reviewer,
            "Critical",
            "openai",
            "gpt-4",
        );

        let provider1 = Arc::new(MockProvider {
            response: "Opus response".to_string(),
        });
        let provider2 = Arc::new(MockProvider {
            response: "Codex response".to_string(),
        });

        engine.spawn_agent(identity1, provider1).unwrap();
        engine.spawn_agent(identity2, provider2).unwrap();

        let engine = Arc::new(engine);
        let router = A2ARouter::new(engine.clone());

        (router, engine)
    }

    #[tokio::test]
    async fn test_route_single() {
        let (router, _) = create_test_router().await;

        let results = router
            .route(
                "user",
                MentionTarget::Single("opus".to_string()),
                "test message",
                vec![],
            )
            .await
            .unwrap();

        assert_eq!(results.len(), 1);
        assert_eq!(results[0].0, "opus");
        assert_eq!(results[0].1, "Opus response");
    }

    #[tokio::test]
    async fn test_route_multiple() {
        let (router, _) = create_test_router().await;

        let results = router
            .route(
                "user",
                MentionTarget::Multiple(vec!["opus".to_string(), "codex".to_string()]),
                "review this",
                vec![],
            )
            .await
            .unwrap();

        assert_eq!(results.len(), 2);
        assert!(results.iter().any(|(name, _)| name == "opus"));
        assert!(results.iter().any(|(name, _)| name == "codex"));
    }

    #[tokio::test]
    async fn test_deadlock_detection() {
        let (router, _) = create_test_router().await;

        let result = router
            .route_single(
                "user",
                "opus",
                "test",
                vec!["opus".to_string()], // opus 已在调用链中
            )
            .await;

        assert!(result.is_err());
        assert!(result.unwrap_err().to_string().contains("Circular call"));
    }

    #[tokio::test]
    async fn test_nonexistent_agent() {
        let (router, _) = create_test_router().await;

        let result = router
            .route(
                "user",
                MentionTarget::Single("nonexistent".to_string()),
                "test",
                vec![],
            )
            .await;

        assert!(result.is_err());
        assert!(result.unwrap_err().to_string().contains("not found"));
    }

    #[test]
    fn test_deadlock_prevention_detect_cycle() {
        let chain: Vec<Arc<str>> = vec!["agent1".into(), "agent2".into()];
        assert!(DeadlockPrevention::detect_cycle(&chain, "agent1"));
        assert!(!DeadlockPrevention::detect_cycle(&chain, "agent3"));
    }

    #[test]
    fn test_a2a_message_creation() {
        let msg = A2AMessage::new(
            "sender",
            Some("receiver"),
            "content",
            vec!["agent1".to_string()],
        );

        assert_eq!(msg.from.as_ref(), "sender");
        assert_eq!(msg.to.as_ref().unwrap().as_ref(), "receiver");
        assert_eq!(msg.content.as_ref(), "content");
        assert_eq!(msg.call_chain.len(), 1);
    }
}
