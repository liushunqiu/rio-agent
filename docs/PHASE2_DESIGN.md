# Rio Agent Phase 2 设计文档

**版本**: v0.1  
**日期**: 2026-06-21  
**状态**: 待审核  
**参考**: Clowder AI (https://github.com/zts212653/clowder-ai)

## 1. 目标概述

在 Phase 1 完成基础 CLI 核心的基础上，Phase 2 的目标是实现多 Agent 协作系统，参考 Clowder AI 的核心架构，但适配 Rust/Tauri 的技术栈。

### 1.1 核心目标

- **多 Agent 编排**: 支持多个 AI Agent 并行工作
- **Agent 持久化身份**: 每个 Agent 保持独立的角色、性格和记忆
- **Agent 间通信 (A2A)**: 支持 @mention 路由和消息传递
- **共享记忆系统**: 建立团队级别的知识库
- **Skills 框架**: 按需加载专用能力

### 1.2 非目标（留待后续 Phase）

- ❌ Web UI（Phase 3）
- ❌ 语音交互（Phase 4）
- ❌ 游戏模式（Phase 4）
- ❌ 多平台集成（Feishu/Telegram）（Phase 4）

## 2. 架构设计

### 2.1 总体架构

```
┌─────────────────────────────────────────────────┐
│                     User                        │
│            (通过 CLI 或后续的 UI)                 │
└──────────────────────┬──────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────┐
│           Rio Agent Platform Layer              │
│                                                 │
│  ┌──────────┐  ┌──────────┐  ┌─────────────┐  │
│  │ Identity │  │   A2A    │  │   Skills    │  │
│  │ Manager  │  │  Router  │  │  Framework  │  │
│  └──────────┘  └──────────┘  └─────────────┘  │
│                                                 │
│  ┌──────────┐  ┌──────────┐  ┌─────────────┐  │
│  │  Shared  │  │   Task   │  │   Agent     │  │
│  │  Memory  │  │  Planner │  │   Engine    │  │
│  └──────────┘  └──────────┘  └─────────────┘  │
└────┬────────────────┬────────────────┬─────────┘
     │                │                │
┌────▼────┐    ┌─────▼─────┐    ┌────▼────┐
│ Claude  │    │  Gemini   │    │  GPT    │
│ (Opus)  │    │ (Thinking)│    │ (Review)│
└─────────┘    └───────────┘    └─────────┘
```

### 2.2 核心组件

#### 2.2.1 Identity Manager（身份管理器）

**职责**:
- 管理每个 Agent 的身份信息（名称、角色、性格）
- 维护 Agent 的长期记忆
- 防止上下文压缩导致的身份丢失

**数据结构**:
```rust
pub struct AgentIdentity {
    pub id: String,
    pub name: String,           // 如 "XianXian"
    pub role: AgentRole,        // Architect, Reviewer, Designer
    pub personality: String,    // 性格描述
    pub provider: AIProvider,   // Claude, GPT, Gemini
    pub model: String,          // 具体模型
    pub created_at: DateTime<Utc>,
}

pub enum AgentRole {
    Architect,   // 架构设计
    Reviewer,    // 代码审查
    Designer,    // UI/UX 设计
    General,     // 通用任务
}
```

**实现要点**:
- 每个 Agent 在 System Prompt 中注入身份信息
- 使用 `rio-storage` 持久化身份数据
- 支持身份的 CRUD 操作

#### 2.2.2 A2A Router（Agent 间路由）

**职责**:
- 解析 @mention 语法（如 `@opus`, `@codex`, `@gemini`）
- 将消息路由到正确的 Agent
- 支持广播消息（`@all`）

**路由规则**:
```rust
pub enum RouteTarget {
    Single(String),        // @opus
    Multiple(Vec<String>), // @opus @codex
    Broadcast,             // @all
    Auto,                  // 自动选择最合适的 Agent
}

pub struct A2AMessage {
    pub from: String,          // 发送者 Agent ID
    pub to: RouteTarget,       // 接收者
    pub content: String,       // 消息内容
    pub context: Vec<Message>, // 上下文
    pub timestamp: DateTime<Utc>,
}
```

**实现策略**:
1. 消息预处理：提取 @mention
2. 身份验证：检查 Agent 是否存在
3. 消息转发：构建目标 Agent 的上下文
4. 响应聚合：收集所有 Agent 的回复

#### 2.2.3 Shared Memory（共享记忆）

**职责**:
- 存储团队级别的知识
- 提供证据库（Evidence Store）
- 支持经验教训（Lessons Learned）

**数据模型**:
```rust
pub struct SharedMemory {
    pub evidence: EvidenceStore,
    pub lessons: LessonStore,
    pub decisions: DecisionLog,
}

pub struct Evidence {
    pub id: String,
    pub title: String,
    pub content: String,
    pub source: String,       // Agent ID
    pub tags: Vec<String>,
    pub created_at: DateTime<Utc>,
}

pub struct Lesson {
    pub id: String,
    pub what_happened: String,
    pub what_learned: String,
    pub apply_when: String,
    pub created_at: DateTime<Utc>,
}
```

**存储方案**:
- SQLite 存储结构化数据
- 全文搜索支持检索
- 版本控制追踪变更

#### 2.2.4 Skills Framework（技能框架）

**职责**:
- 按需加载专用技能
- 支持技能的动态注入
- 管理技能的生命周期

**技能定义**:
```rust
pub struct Skill {
    pub name: String,
    pub description: String,
    pub prompt: String,        // 要注入的 System Prompt
    pub required_tools: Vec<String>,
    pub contexts: Vec<String>, // 适用场景
}

// 内置技能示例
pub const TDD_SKILL: &str = r#"
You are in TDD mode. Follow these steps:
1. Write failing tests first
2. Implement minimal code to pass
3. Refactor with confidence
"#;

pub const CODE_REVIEW_SKILL: &str = r#"
You are reviewing code. Check for:
1. Correctness bugs
2. Security vulnerabilities
3. Performance issues
4. Code smells
"#;
```

**使用方式**:
```bash
# CLI 命令
rio-cli chat --skill tdd "Implement user authentication"
rio-cli chat --skill code-review "Review the auth changes"
```

### 2.3 数据流

```
User Input
    ↓
[A2A Router 解析 @mention]
    ↓
[Identity Manager 加载 Agent 身份]
    ↓
[Skills Framework 注入技能]
    ↓
[Shared Memory 提供上下文]
    ↓
[Agent Engine 执行]
    ↓
[结果存储到 Shared Memory]
    ↓
User Output
```

## 3. 实现计划

### 3.1 模块划分

| Crate | 职责 | 依赖 |
|-------|------|------|
| `rio-identity` | 身份管理 | rio-core, rio-storage |
| `rio-router` | A2A 路由 | rio-core, rio-identity |
| `rio-memory` | 共享记忆 | rio-core, rio-storage |
| `rio-skills` | 技能框架 | rio-core |

### 3.2 实现顺序

#### Week 1: 身份系统
- [ ] 创建 `rio-identity` crate
- [ ] 实现 `AgentIdentity` 数据结构
- [ ] 实现身份的 CRUD 操作
- [ ] SQLite 持久化
- [ ] 单元测试

#### Week 2: A2A 路由
- [ ] 创建 `rio-router` crate
- [ ] 实现 @mention 解析
- [ ] 实现路由逻辑
- [ ] 支持多 Agent 并发执行
- [ ] 集成测试

#### Week 3: 共享记忆
- [ ] 创建 `rio-memory` crate
- [ ] 实现 Evidence Store
- [ ] 实现 Lessons Store
- [ ] 实现 Decision Log
- [ ] 全文搜索功能

#### Week 4: Skills 框架
- [ ] 创建 `rio-skills` crate
- [ ] 实现技能加载机制
- [ ] 创建内置技能（TDD, Review, Debug）
- [ ] CLI 集成
- [ ] 端到端测试

### 3.3 成功标准

**功能完整性**:
- ✅ 可以创建和管理多个 Agent
- ✅ 支持 @mention 路由消息
- ✅ Agent 可以访问共享记忆
- ✅ 可以按需加载技能

**性能指标**:
- ✅ Agent 创建 < 100ms
- ✅ 消息路由 < 50ms
- ✅ 记忆检索 < 200ms

**代码质量**:
- ✅ 所有 crate 测试覆盖率 > 80%
- ✅ 通过 cargo clippy 检查
- ✅ 通过代码审核

## 4. 风险和缓解

### 4.1 技术风险

| 风险 | 影响 | 概率 | 缓解措施 |
|------|------|------|----------|
| 多 Agent 并发冲突 | 高 | 中 | 使用消息队列隔离，增加事务锁 |
| 记忆检索性能 | 中 | 中 | 使用全文索引，缓存热点数据 |
| Skills 注入不生效 | 中 | 低 | 充分测试，提供调试模式 |

### 4.2 架构风险

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| 过度复杂化 | 中 | 参考 Clowder 简化设计，MVP 优先 |
| 与 Phase 1 不兼容 | 高 | 向后兼容，保留原有 CLI 接口 |

## 5. 与 Clowder AI 的差异

### 5.1 相同点
- ✅ 多 Agent 编排
- ✅ 持久化身份
- ✅ A2A 通信
- ✅ 共享记忆
- ✅ Skills 框架

### 5.2 差异点

| 特性 | Clowder AI | Rio Agent Phase 2 | 原因 |
|------|------------|-------------------|------|
| 技术栈 | Node.js + TypeScript | Rust + Tauri | 性能和跨平台 |
| UI | React Web UI | CLI only | 分阶段实现 |
| 游戏模式 | Werewolf, Pixel Brawl | ❌ | 不是核心功能 |
| 语音交互 | TTS/ASR | ❌ | Phase 4 |
| Redis | 必需 | 可选 | SQLite 足够 |

## 6. 审核要点

### 6.1 架构审核
- [ ] 模块划分是否合理？
- [ ] 数据流是否清晰？
- [ ] 是否有过度设计？

### 6.2 实现可行性
- [ ] Rust 生态是否支持所需功能？
- [ ] 4 周时间是否可行？
- [ ] 是否需要引入新的依赖？

### 6.3 兼容性
- [ ] 与 Phase 1 是否兼容？
- [ ] 是否影响现有功能？
- [ ] 是否需要数据库迁移？

### 6.4 安全性
- [ ] Agent 间通信是否安全？
- [ ] 共享记忆是否有权限控制？
- [ ] Skills 注入是否有风险？

---

**下一步**: 
1. 提交此文档到 code-review 审核
2. 根据反馈调整设计
3. 开始实现 Week 1 任务
