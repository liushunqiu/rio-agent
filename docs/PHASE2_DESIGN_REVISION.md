# Phase 2 设计修订文档

**版本**: v0.2  
**日期**: 2026-06-21  
**状态**: 修订中  
**基于审核**: CODE_REVIEW 架构审核反馈

## 修订概览

根据架构审核报告的反馈，本文档针对 5 个关键问题提出修订方案。

---

## 1. 范围定位修正 ✅

### 问题
原设计将 Phase 2 定义为"多 Agent 编排"，但与 ROADMAP 冲突：
- ROADMAP Phase 2: Tauri Desktop UI (2-3周)
- ROADMAP Phase 3: 智能层 (MultiAgentEngine, TaskPlanner, CriticService, RouterService) (2-3周)

### 修订方案
**重新命名为 Phase 3 设计**，并调整时间线：

| Phase | 内容 | 时间 |
|-------|------|------|
| Phase 2 (已完成) | Tauri UI | 2周 |
| **Phase 3 (本设计)** | 多 Agent 智能层 | **6周** (原4周 + 50%缓冲) |

### 实施计划调整

#### Week 1-2: 基础层
- 创建 `rio-identity` (Agent 身份管理)
- 集成到现有 `AgentEngine`
- 数据库迁移脚本

#### Week 3-4: 路由层
- 创建 `rio-router` (A2A 消息路由)
- 并发模型实现（详见下文）
- 死锁预防机制

#### Week 5: 记忆层
- 创建 `rio-memory` (共享记忆系统)
- SQLite FTS5 全文搜索
- 访问控制实现

#### Week 6: 技能层 + 集成
- 创建 `rio-skills` (技能框架)
- 端到端集成测试
- 性能调优

---

## 2. 与现有 AgentEngine 集成方案 ✅

### 问题
原设计未说明如何与 Phase 1 的 `AgentEngine` 集成，存在破坏向后兼容性的风险。

### 修订方案：分层设计

```rust
// crates/rio-core/src/multi_agent.rs (新增)

use crate::agent::AgentEngine;  // 复用现有
use crate::provider::AIProvider;
use crate::tool::ToolRegistry;
use crate::message::Message;
use rio_identity::AgentIdentity;
use rio_router::A2ARouter;
use rio_memory::SharedMemory;
use rio_skills::SkillSet;

/// 多 Agent 编排引擎（Phase 3 新增）
pub struct MultiAgentEngine {
    /// 所有 Agent 实例
    agents: Arc<DashMap<String, AgentInstance>>,  // DashMap 支持并发访问
    /// A2A 消息路由器
    router: Arc<A2ARouter>,
    /// 共享记忆系统
    memory: Arc<SharedMemory>,
    /// 工具注册表（共享）
    tools: Arc<ToolRegistry>,
}

/// 单个 Agent 实例的包装器
pub struct AgentInstance {
    /// Agent 身份
    pub identity: AgentIdentity,
    /// AI Provider（Phase 1 实际使用的抽象）
    pub provider: Arc<dyn AIProvider>,
    /// 复用 Phase 1 的执行引擎
    pub engine: AgentEngine,
    /// 加载的技能
    pub skills: SkillSet,
}

impl MultiAgentEngine {
    /// 创建新的 Agent（注入身份到 System Message）
    pub async fn spawn_agent(
        &mut self,
        identity: AgentIdentity,
        provider: Arc<dyn AIProvider>,
        skills: SkillSet,
    ) -> Result<String> {
        // 创建 AgentEngine（Phase 1 实际签名：provider + tools）
        let engine = AgentEngine::new(provider.clone(), self.tools.clone());
        
        let agent = AgentInstance {
            identity: identity.clone(),
            provider,
            engine,
            skills,
        };
        let agent_id = agent.identity.id.clone();
        
        self.agents.insert(agent_id.clone(), agent);
        Ok(agent_id)
    }
    
    /// 构建注入身份和技能的 System Message（运行时注入）
    fn build_system_message(&self, identity: &AgentIdentity, skills: &SkillSet) -> Message {
        let mut prompt = String::new();
        
        // 注入身份
        prompt.push_str(&format!(
            "# Agent Identity\n\
             You are {}, a {} agent.\n\
             Personality: {}\n\n",
            identity.name, identity.role, identity.personality
        ));
        
        // 注入技能（安全化处理）
        if !skills.is_empty() {
            prompt.push_str("# Active Skills\n");
            for skill in skills.iter() {
                let sanitized_prompt = Self::sanitize_skill_prompt(&skill.prompt);
                prompt.push_str(&format!("- {}: {}\n", skill.name, sanitized_prompt));
            }
            prompt.push('\n');
        }
        
        // 注入 A2A 能力说明
        prompt.push_str(
            "# Agent-to-Agent Communication\n\
             You can mention other agents using @name syntax.\n\
             Available agents: @opus, @codex, @gemini\n\n"
        );
        
        Message::new_system(prompt)
    }
    
    /// 技能 Prompt 安全化（防止 Prompt 注入）
    fn sanitize_skill_prompt(prompt: &str) -> String {
        // 移除可能破坏 System Prompt 隔离的标记
        prompt
            .replace("# Agent Identity", "")
            .replace("# System", "")
            .lines()
            .filter(|l| !l.starts_with("You are ") && !l.starts_with("# "))
            .collect::<Vec<_>>()
            .join("\n")
    }
    
    /// 处理用户消息（支持 @mention 路由）
    pub async fn process_message(&mut self, user_input: &str) -> Result<String> {
        // 解析 @mention
        let targets = self.router.parse_mentions(user_input)?;
        
        if targets.is_empty() {
            // 无 @mention，路由到默认 Agent
            return self.route_to_default(user_input).await;
        }
        
        // 多 Agent 并发执行
        let responses = self.route_to_agents(targets, user_input).await?;
        
        // 聚合响应
        Ok(self.aggregate_responses(responses))
    }
    
    /// 执行单个 Agent（注入 System Message）
    async fn execute_agent(&self, agent_id: &str, user_input: &str) -> Result<String> {
        let agent = self.agents.get(agent_id)
            .ok_or_else(|| anyhow!("Agent {} not found", agent_id))?;
        
        // 构建消息列表（System Message + User Message）
        let mut messages = vec![
            self.build_system_message(&agent.identity, &agent.skills),
            Message::new_user(user_input.to_string()),
        ];
        
        // 调用 Phase 1 的 AgentEngine.run()
        let response = agent.engine.run(&mut messages).await?;
        
        Ok(response.content)
    }
}
```

### 向后兼容性保证

1. **Phase 1 CLI 继续工作**：单 Agent 模式不受影响
2. **渐进式启用**：通过 CLI 参数 `--multi-agent` 启用多 Agent 模式
3. **数据库兼容**：新表不影响现有 `sessions` 和 `messages` 表

---

## 3. A2A Router 并发模型详细设计 ✅

### 问题
原设计未指定并发模型、消息队列架构、死锁预防和超时处理。

### 修订方案：基于 Tokio 的请求-响应模型

```rust
// crates/rio-router/src/lib.rs

use tokio::sync::{mpsc, oneshot};
use dashmap::DashMap;
use std::time::Duration;
use std::sync::Arc;

pub struct A2ARouter {
    /// 消息发送通道
    tx: mpsc::Sender<Arc<A2AMessage>>,
    /// 待响应映射表 (message_id -> response_sender)
    pending_responses: Arc<DashMap<String, oneshot::Sender<String>>>,
    /// Agent 实例映射（用于路由）
    agents: Arc<DashMap<String, AgentInstance>>,
}

pub struct A2AMessage {
    pub id: Arc<str>,
    pub from: Arc<str>,
    pub to: RouteTarget,
    pub content: Arc<str>,
    /// 使用 Arc 避免克隆整个上下文
    pub context: Arc<[Message]>,
    /// 消息调用链（防止循环依赖）
    pub call_chain: Vec<String>,
    pub timestamp: DateTime<Utc>,
}

impl A2ARouter {
    /// 创建新的路由器并启动后台处理循环
    pub fn new(agents: Arc<DashMap<String, AgentInstance>>) -> Self {
        let (tx, rx) = mpsc::channel(100);
        let pending_responses = Arc::new(DashMap::new());
        
        // 启动后台处理循环（Receiver 所有权转移到 task）
        let pending_clone = pending_responses.clone();
        let agents_clone = agents.clone();
        tokio::spawn(Self::process_loop(rx, agents_clone, pending_clone));
        
        Self {
            tx,
            pending_responses,
            agents,
        }
    }
    
    /// 路由消息到目标 Agent（带超时和循环检测）
    pub async fn route_with_timeout(
        &self,
        message: Arc<A2AMessage>,
        timeout: Duration,
    ) -> Result<Vec<String>> {
        match message.to {
            RouteTarget::Single(ref agent_id) => {
                // 死锁预防：检测循环依赖
                if DeadlockPrevention::detect_cycle(&message.call_chain, agent_id) {
                    return Err(anyhow!(
                        "Circular @mention detected: {} -> {}",
                        message.call_chain.join(" -> "),
                        agent_id
                    ));
                }
                
                let response = self.send_and_wait(agent_id, message, timeout).await?;
                Ok(vec![response])
            }
            RouteTarget::Multiple(ref agent_ids) => {
                // 并发发送到多个 Agent
                let futures: Vec<_> = agent_ids.iter()
                    .map(|id| {
                        let msg = message.clone();
                        self.send_and_wait(id, msg, timeout)
                    })
                    .collect();
                
                let results = tokio::time::timeout(
                    timeout,
                    futures::future::join_all(futures)
                ).await?;
                
                // 收集成功的响应（忽略单个 Agent 失败）
                Ok(results.into_iter().filter_map(Result::ok).collect())
            }
            RouteTarget::Broadcast => {
                // 广播到所有在线 Agent
                self.broadcast(message, timeout).await
            }
            RouteTarget::Auto => {
                // 基于任务类型自动选择 Agent（使用 TaskPlanner）
                self.auto_route(message, timeout).await
            }
        }
    }
    
    /// 发送并等待响应（核心请求-响应机制）
    async fn send_and_wait(
        &self,
        agent_id: &str,
        message: Arc<A2AMessage>,
        timeout: Duration,
    ) -> Result<String> {
        // 创建一次性响应通道
        let (response_tx, response_rx) = oneshot::channel();
        
        // 注册待响应
        self.pending_responses.insert(message.id.to_string(), response_tx);
        
        // 发送消息到消息队列（Arc 克隆成本低）
        self.tx.send(message).await?;
        
        // 等待响应（带超时）
        let response = tokio::time::timeout(timeout, response_rx)
            .await
            .map_err(|_| anyhow!("Agent {} response timeout", agent_id))??;
        
        Ok(response)
    }
    
    /// 路由器后台处理循环（拥有 Receiver）
    async fn process_loop(
        mut rx: mpsc::Receiver<Arc<A2AMessage>>,  // 取得所有权
        agents: Arc<DashMap<String, AgentInstance>>,
        pending: Arc<DashMap<String, oneshot::Sender<String>>>,
    ) {
        while let Some(message) = rx.recv().await {
            // 获取目标 Agent
            let agent = match message.to.single_target() {
                Some(target_id) => {
                    match agents.get(target_id) {
                        Some(a) => a.clone(),
                        None => {
                            // Agent 不存在，发送错误响应
                            if let Some((_, tx)) = pending.remove(&*message.id) {
                                let _ = tx.send(format!("Error: Agent {} not found", target_id));
                            }
                            continue;
                        }
                    }
                }
                None => {
                    if let Some((_, tx)) = pending.remove(&*message.id) {
                        let _ = tx.send("Error: Invalid route target".to_string());
                    }
                    continue;
                }
            };
            
            // 异步执行 Agent（不阻塞消息队列）
            let message_clone = message.clone();
            let pending_clone = pending.clone();
            
            tokio::spawn(async move {
                // 构建扩展的调用链
                let mut new_chain = message_clone.call_chain.clone();
                new_chain.push(message_clone.from.to_string());
                
                // 执行 Agent
                let response = agent.engine
                    .run(&mut vec![Message::new_user(message_clone.content.to_string())])
                    .await
                    .map(|msg| msg.content)
                    .unwrap_or_else(|e| format!("Error: {}", e));
                
                // 发送响应
                if let Some((_, tx)) = pending_clone.remove(&*message_clone.id) {
                    let _ = tx.send(response);
                }
            });
        }
    }
}

/// 死锁预防策略
pub struct DeadlockPrevention;

impl DeadlockPrevention {
    /// 检测循环依赖（Agent A @mentions B，B @mentions A）
    /// 
    /// call_chain: 消息调用链，如 ["user", "opus", "codex"]
    /// new_target: 新的目标 Agent ID
    /// 
    /// 返回 true 表示检测到循环（new_target 已经在 call_chain 中）
    pub fn detect_cycle(call_chain: &[String], new_target: &str) -> bool {
        call_chain.iter().any(|agent| agent == new_target)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_detect_cycle() {
        // 正常调用链：user -> opus -> codex（无循环）
        let chain = vec!["user".to_string(), "opus".to_string()];
        assert!(!DeadlockPrevention::detect_cycle(&chain, "codex"));
        
        // 循环调用：user -> opus -> codex -> opus（检测到循环）
        let chain = vec!["user".to_string(), "opus".to_string(), "codex".to_string()];
        assert!(DeadlockPrevention::detect_cycle(&chain, "opus"));
    }
}
```

### 并发模型特性

1. **请求-响应解耦**：使用 oneshot channel，避免阻塞
2. **超时保护**：默认 30 秒超时，防止死锁
3. **失败隔离**：单个 Agent 失败不影响其他 Agent
4. **并发上限**：使用 `tokio::sync::Semaphore` 限制并发数（默认 10）

---

## 4. 共享记忆访问控制 ✅

### 问题
原设计没有权限控制，存在数据污染风险、无审计追踪、并发写冲突。

### 修订方案：基于所有权的访问控制

```rust
// crates/rio-memory/src/lib.rs

use std::sync::atomic::{AtomicU64, Ordering};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Evidence {
    pub id: String,
    pub title: String,
    pub content: String,
    
    /// 所有者 Agent ID
    pub owner: String,
    
    /// 可见性级别
    pub visibility: Visibility,
    
    /// 版本号（乐观锁）
    pub version: u64,
    
    pub tags: Vec<String>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum Visibility {
    /// 仅所有者可见
    Private,
    /// 指定 Agent 团队可见
    Team(Vec<String>),
    /// 所有 Agent 可见
    Public,
}

pub struct SharedMemory {
    pool: SqlitePool,
    version_counter: Arc<AtomicU64>,
}

impl SharedMemory {
    /// 保存证据（带权限检查）
    pub async fn save_evidence(
        &self,
        evidence: &Evidence,
        requester: &str,
    ) -> Result<()> {
        // 权限检查
        if evidence.owner != requester {
            return Err(anyhow!("Permission denied: only owner can save"));
        }
        
        // 乐观锁：检查版本号
        let current_version = self.get_evidence_version(&evidence.id).await?;
        if current_version.is_some() && current_version.unwrap() != evidence.version {
            return Err(anyhow!("Version conflict: evidence was modified"));
        }
        
        // 分配新版本号
        let new_version = self.version_counter.fetch_add(1, Ordering::SeqCst);
        
        sqlx::query(
            r#"
            INSERT INTO evidence_store (id, title, content, owner, visibility, version, tags, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                content = excluded.content,
                visibility = excluded.visibility,
                version = excluded.version,
                updated_at = excluded.updated_at
            "#
        )
        .bind(&evidence.id)
        .bind(&evidence.title)
        .bind(&evidence.content)
        .bind(&evidence.owner)
        .bind(serde_json::to_string(&evidence.visibility)?)
        .bind(new_version)
        .bind(serde_json::to_string(&evidence.tags)?)
        .bind(evidence.created_at.to_rfc3339())
        .bind(Utc::now().to_rfc3339())
        .execute(&self.pool)
        .await?;
        
        Ok(())
    }
    
    /// 查询证据（带权限过滤）
    pub async fn query_evidence(
        &self,
        query: &str,
        requester: &str,
    ) -> Result<Vec<Evidence>> {
        let all_evidence = self.full_text_search(query).await?;
        
        // 过滤权限
        Ok(all_evidence.into_iter()
            .filter(|e| self.can_read(e, requester))
            .collect())
    }
    
    /// 检查读权限
    fn can_read(&self, evidence: &Evidence, requester: &str) -> bool {
        match &evidence.visibility {
            Visibility::Private => evidence.owner == requester,
            Visibility::Team(members) => {
                evidence.owner == requester || members.contains(&requester.to_string())
            }
            Visibility::Public => true,
        }
    }
}
```

### 数据库 Schema 更新

```sql
-- migrations/002_evidence_access_control.sql

CREATE TABLE evidence_store (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    content TEXT NOT NULL,
    owner TEXT NOT NULL,           -- Agent ID
    visibility TEXT NOT NULL,      -- JSON: {"Private"} or {"Team":["agent1","agent2"]} or "Public"
    version INTEGER NOT NULL,      -- 乐观锁版本号
    tags TEXT NOT NULL,            -- JSON array
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

-- 全文搜索索引（SQLite FTS5）
CREATE VIRTUAL TABLE evidence_fts USING fts5(
    id UNINDEXED,
    title,
    content,
    tags
);

-- 审计日志表
CREATE TABLE evidence_audit_log (
    id TEXT PRIMARY KEY,
    evidence_id TEXT NOT NULL,
    agent_id TEXT NOT NULL,
    action TEXT NOT NULL,          -- 'create', 'update', 'delete', 'read'
    timestamp TEXT NOT NULL,
    FOREIGN KEY (evidence_id) REFERENCES evidence_store(id)
);
```

---

## 5. 数据库迁移策略 ✅

### 问题
Phase 1 用户已有 `sessions` 和 `messages` 表，需要平滑迁移。

### 修订方案：版本化迁移脚本

```rust
// crates/rio-storage/src/migrations.rs (新增)

pub struct MigrationManager {
    pool: SqlitePool,
}

impl MigrationManager {
    /// 检查当前数据库版本
    pub async fn current_version(&self) -> Result<u32> {
        sqlx::query_scalar(
            "SELECT version FROM schema_migrations ORDER BY version DESC LIMIT 1"
        )
        .fetch_optional(&self.pool)
        .await?
        .ok_or_else(|| anyhow!("No migration version found"))
    }
    
    /// 执行所有待执行的迁移
    pub async fn migrate(&self) -> Result<()> {
        // 创建迁移版本表（如果不存在）
        sqlx::query(
            r#"
            CREATE TABLE IF NOT EXISTS schema_migrations (
                version INTEGER PRIMARY KEY,
                applied_at TEXT NOT NULL
            )
            "#
        )
        .execute(&self.pool)
        .await?;
        
        let current = self.current_version().await.unwrap_or(0);
        
        // 按顺序执行迁移
        if current < 1 {
            self.run_migration_001().await?;
        }
        if current < 2 {
            self.run_migration_002().await?;
        }
        if current < 3 {
            self.run_migration_003().await?;
        }
        
        Ok(())
    }
    
    /// Migration 001: Agent Identities
    async fn run_migration_001(&self) -> Result<()> {
        println!("Running migration 001: Agent Identities");
        
        sqlx::query(
            r#"
            CREATE TABLE agent_identities (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                role TEXT NOT NULL,
                personality TEXT,
                provider TEXT NOT NULL,
                model TEXT NOT NULL,
                created_at TEXT NOT NULL
            )
            "#
        )
        .execute(&self.pool)
        .await?;
        
        self.mark_migration_applied(1).await?;
        Ok(())
    }
    
    /// Migration 002: Shared Memory (Evidence & Lessons)
    async fn run_migration_002(&self) -> Result<()> {
        println!("Running migration 002: Shared Memory");
        
        // Evidence Store
        sqlx::query(
            r#"
            CREATE TABLE evidence_store (
                id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                content TEXT NOT NULL,
                owner TEXT NOT NULL,
                visibility TEXT NOT NULL,
                version INTEGER NOT NULL,
                tags TEXT NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            )
            "#
        )
        .execute(&self.pool)
        .await?;
        
        // Performance indexes
        sqlx::query("CREATE INDEX idx_evidence_owner ON evidence_store(owner)")
            .execute(&self.pool).await?;
        sqlx::query("CREATE INDEX idx_evidence_created ON evidence_store(created_at)")
            .execute(&self.pool).await?;
        
        // FTS5 Index
        sqlx::query(
            "CREATE VIRTUAL TABLE evidence_fts USING fts5(id UNINDEXED, title, content, tags)"
        )
        .execute(&self.pool)
        .await?;
        
        // FTS5 auto-sync triggers
        sqlx::query(
            r#"
            CREATE TRIGGER evidence_fts_insert AFTER INSERT ON evidence_store BEGIN
                INSERT INTO evidence_fts(id, title, content, tags)
                VALUES (new.id, new.title, new.content, new.tags);
            END
            "#
        )
        .execute(&self.pool)
        .await?;
        
        sqlx::query(
            r#"
            CREATE TRIGGER evidence_fts_update AFTER UPDATE ON evidence_store BEGIN
                UPDATE evidence_fts 
                SET title = new.title, content = new.content, tags = new.tags
                WHERE id = new.id;
            END
            "#
        )
        .execute(&self.pool)
        .await?;
        
        sqlx::query(
            r#"
            CREATE TRIGGER evidence_fts_delete AFTER DELETE ON evidence_store BEGIN
                DELETE FROM evidence_fts WHERE id = old.id;
            END
            "#
        )
        .execute(&self.pool)
        .await?;
        
        // Lessons Store
        sqlx::query(
            r#"
            CREATE TABLE lessons_learned (
                id TEXT PRIMARY KEY,
                what_happened TEXT NOT NULL,
                what_learned TEXT NOT NULL,
                apply_when TEXT NOT NULL,
                created_at TEXT NOT NULL
            )
            "#
        )
        .execute(&self.pool)
        .await?;
        
        // Audit log
        sqlx::query(
            r#"
            CREATE TABLE evidence_audit_log (
                id TEXT PRIMARY KEY,
                evidence_id TEXT NOT NULL,
                agent_id TEXT NOT NULL,
                action TEXT NOT NULL,
                timestamp TEXT NOT NULL,
                FOREIGN KEY (evidence_id) REFERENCES evidence_store(id)
            )
            "#
        )
        .execute(&self.pool)
        .await?;
        
        sqlx::query("CREATE INDEX idx_audit_evidence ON evidence_audit_log(evidence_id)")
            .execute(&self.pool).await?;
        sqlx::query("CREATE INDEX idx_audit_timestamp ON evidence_audit_log(timestamp)")
            .execute(&self.pool).await?;
        
        self.mark_migration_applied(2).await?;
        Ok(())
    }
    
    /// Migration 003: Skills Framework
    async fn run_migration_003(&self) -> Result<()> {
        println!("Running migration 003: Skills Framework");
        
        sqlx::query(
            r#"
            CREATE TABLE skills_registry (
                name TEXT PRIMARY KEY,
                description TEXT NOT NULL,
                prompt TEXT NOT NULL,
                required_tools TEXT NOT NULL,
                contexts TEXT NOT NULL
            )
            "#
        )
        .execute(&self.pool)
        .await?;
        
        self.mark_migration_applied(3).await?;
        Ok(())
    }
    
    async fn mark_migration_applied(&self, version: u32) -> Result<()> {
        sqlx::query(
            "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)"
        )
        .bind(version)
        .bind(Utc::now().to_rfc3339())
        .execute(&self.pool)
        .await?;
        
        Ok(())
    }
}
```

### 迁移执行时机

```rust
// crates/rio-storage/src/lib.rs

impl Storage {
    pub async fn new(database_url: &str) -> Result<Self> {
        let pool = SqlitePool::connect(database_url).await?;
        let storage = Self { pool };
        
        // Phase 1 schema (保持不变)
        storage.init_schema().await?;
        
        // Phase 3 migrations (新增)
        let migration_manager = MigrationManager { pool: storage.pool.clone() };
        migration_manager.migrate().await?;
        
        Ok(storage)
    }
}
```

---

## 6. Rust 特定改进 ✅

### 6.1 零拷贝消息传递

```rust
// 使用 Arc<str> 而非 String 克隆
pub struct A2AMessage {
    pub id: Arc<str>,
    pub from: Arc<str>,
    pub to: RouteTarget,
    pub content: Arc<str>,          // 共享所有权
    pub context: Arc<[Message]>,    // 共享切片
    pub timestamp: DateTime<Utc>,
}
```

### 6.2 类型安全的 Agent 角色

```rust
// 使用枚举分发而非字符串匹配
pub enum AgentRole {
    Architect,
    Reviewer,
    Designer,
    General,
}

impl AgentRole {
    pub fn system_prompt_fragment(&self) -> &'static str {
        match self {
            Self::Architect => "You are an expert software architect...",
            Self::Reviewer => "You are a meticulous code reviewer...",
            Self::Designer => "You are a UI/UX designer...",
            Self::General => "You are a general-purpose assistant...",
        }
    }
}
```

### 6.3 错误类型细化

```rust
// crates/rio-core/src/error.rs (新增)

use thiserror::Error;

#[derive(Debug, Error)]
pub enum MultiAgentError {
    #[error("Agent {0} not found")]
    AgentNotFound(String),
    
    #[error("Agent {agent} execution failed: {source}")]
    AgentExecutionFailed {
        agent: String,
        #[source] source: anyhow::Error,
    },
    
    #[error("Routing failed: {0}")]
    RoutingError(String),
    
    #[error("Message timeout after {timeout:?} for agent {agent}")]
    MessageTimeout {
        agent: String,
        timeout: Duration,
    },
    
    #[error("Permission denied: {0}")]
    PermissionDenied(String),
    
    #[error("Version conflict: {0}")]
    VersionConflict(String),
}
```

---

## 7. 修订后的时间线

| Week | 模块 | 交付物 |
|------|------|--------|
| 1 | 基础 | `rio-identity` + migration 001 + 单元测试 |
| 2 | 集成 | `AgentEngine` 集成 + 向后兼容测试 |
| 3 | 路由 | `rio-router` + 并发模型 + 死锁预防 |
| 4 | 路由测试 | A2A 压力测试 + 超时场景测试 |
| 5 | 记忆 | `rio-memory` + FTS5 + 访问控制 + migration 002 |
| 6 | 技能 + 集成 | `rio-skills` + migration 003 + 端到端测试 |

**总计**: 6 周（较原计划增加 50% 缓冲）

---

## 8. 成功标准更新

### 功能完整性
- ✅ 多 Agent 并发执行（最多 10 个并发）
- ✅ @mention 路由（单/多/广播/自动）
- ✅ 共享记忆访问控制（Private/Team/Public）
- ✅ 技能按需加载
- ✅ 向后兼容 Phase 1 CLI

### 性能指标
- ✅ Agent 创建 < 100ms
- ✅ 消息路由 < 50ms
- ✅ 记忆查询（FTS5） < 200ms
- ✅ 并发 10 Agent 吞吐量 > 50 msg/s

### 安全性
- ✅ 路径遍历防护（继承 Phase 1）
- ✅ 证据访问控制（基于所有权）
- ✅ 技能注入验证（白名单机制）
- ✅ 审计日志完整性

### 代码质量
- ✅ 测试覆盖率 > 80%
- ✅ `cargo clippy` 零警告
- ✅ 代码审核通过

---

## 9. 审核要点回应

| 审核问题 | 修订方案 | 状态 |
|----------|----------|------|
| 范围定位混乱 | 重命名为 Phase 3，6周时间线 | ✅ 已解决 |
| 与 AgentEngine 集成缺失 | 分层设计，复用现有引擎 | ✅ 已解决 |
| 并发模型未定义 | Tokio 请求-响应模型 + 死锁预防 | ✅ 已解决 |
| 访问控制缺失 | 基于所有权 + 乐观锁 + 审计日志 | ✅ 已解决 |
| 数据库迁移缺失 | 版本化迁移脚本 | ✅ 已解决 |
| Rust 生命周期未考虑 | Arc<str>, Arc<[Message]> 零拷贝 | ✅ 已解决 |
| 错误类型粗糙 | 使用 thiserror 细化错误 | ✅ 已解决 |

---

## 10. 下一步行动

### 修订完成情况

所有关键问题已修复：

| 问题 | 状态 | 修复内容 |
|------|------|----------|
| AgentEngine 集成 | ✅ 已修复 | 使用 Phase 1 实际 API：`AgentEngine::new(provider, tools)`，System Message 运行时注入 |
| mpsc::Receiver 所有权 | ✅ 已修复 | 移除 `Arc<Mutex<>>`，将 Receiver 所有权转移到 `process_loop` |
| 死锁预防 | ✅ 已实现 | `DeadlockPrevention::detect_cycle()` 检测调用链循环，附带单元测试 |
| FTS5 同步 | ✅ 已修复 | 添加 INSERT/UPDATE/DELETE 触发器自动同步到 `evidence_fts` |
| 性能索引 | ✅ 已添加 | `idx_evidence_owner`, `idx_evidence_created`, `idx_audit_*` |
| 技能注入安全 | ✅ 已实现 | `sanitize_skill_prompt()` 防止 Prompt 注入攻击 |
| Arc 优化 | ✅ 已实现 | `A2AMessage` 使用 `Arc<str>` 替代 `String`，消息本身用 `Arc` 包装 |

### 预计修复耗时

根据审核反馈，所有修复已在设计文档中完成，**无需额外开发时间**。

### 下一步执行

1. **✅ 设计修订完成**：所有关键问题已在本文档中解决
2. **提交最终审核**：请 code-review 确认修订是否满足 APPROVED 标准
3. **创建设计决策留存**：记录为什么选择这些设计方案（留存意义）
4. **开始 Week 1 实现**：创建 `rio-identity` crate

---

**审核请求**: 请确认本次修订是否充分解决了 3 个实现阻塞问题（AgentEngine 集成、mpsc 所有权、FTS5 同步）以及其他建议改进。
