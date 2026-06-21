# Rio Agent

<div align="center">

**跨平台 AI 编程助手 · Rust · Tauri**

多 AI 提供商 · 多 Agent 协作 · 流式输出 · 8 种内置工具

[快速开始](#快速开始) · [核心特性](#核心特性) · [架构设计](#架构设计) · [开发指南](#开发指南)

</div>

---

## 系统要求

- **Rust**: 1.75+
- **Node.js**: 18+ (GUI 开发)
- **平台**: macOS, Windows, Linux

## 快速开始

### CLI 模式

```bash
# 构建
cargo build --release

# 运行 CLI
cargo run --bin rio-cli

# 运行测试
cargo test

# 代码检查
cargo clippy -- -D warnings
```

### GUI 模式（Tauri）

```bash
# 一键启动开发服务器
./start-gui.sh

# 或手动启动
cd rio-agent-ui
npm install
npm run tauri:dev
```

**环境变量**：
```bash
export ANTHROPIC_API_KEY='your-api-key-here'
```

---

## 核心特性

### 🤖 双引擎架构

- **单 Agent 引擎（AgentEngine）**  
  处理简单到中等复杂度任务，支持流式输出、工具调用循环（最多 100 次迭代）、错误处理

- **多 Agent 引擎（MultiAgentEngine）**  
  复杂任务自动分解到多个专业 Agent，支持 Agent-to-Agent（A2A）通信、DAG 编排、死锁预防

### 🔧 8 种内置工具

| 工具 | 功能 | 风险等级 |
|------|------|---------|
| `read_file` | 读取文件内容 | safe |
| `write_file` | 写入文件 | normal |
| `edit_file` | 编辑文件（部分替换） | normal |
| `apply_patch` | 应用 diff 补丁 | normal |
| `execute_command` | 执行 shell 命令 | 分级 |
| `search_files` | 内容搜索（grep） | safe |
| `find_files` | 文件名搜索 | safe |
| `list_directory` | 列出目录 | safe |

**命令风险分类**：
- **safe**: 只读命令（ls, cat, grep, git status）
- **normal**: 大部分命令（npm install, cargo build）
- **dangerous**: 危险命令（rm -rf, sudo, curl, wget）

### 🌐 多 AI 提供商

| 提供商 | 模型 | 特性 |
|--------|------|------|
| **Claude** | Sonnet/Opus 3.x/4.x | thinking mode, 200K context |
| **OpenAI** | GPT-4.x, o1/o3 | vision, JSON mode, 1M context |
| **Gemini** | 1.5/2.x | vision, JSON mode, 1M context |
| **DeepSeek** | v3/r1 | thinking mode, 64K context |

### 🧠 多 Agent 协作

- **Agent 角色系统** - Orchestrator（协调）、Executor（执行）、Reviewer（审查）、Researcher（研究）
- **@mention 路由** - `@agent_name`、`@agent1 @agent2`、`@all`
- **共享内存系统** - Evidence Store（事实）、Lessons Store（经验）、Decision Store（决策）
- **死锁预防** - 调用链追踪，防止 A→B→A 循环

### 💾 安全存储

- **API Key**: 操作系统原生 Keychain（macOS Keychain, Windows Credential Manager, Linux Secret Service）
- **配置元数据**: SQLite 数据库
- **对话历史**: SQLite 持久化

---

## 架构设计

### 模块化 Crate 架构

```
rio-agent/
├── crates/
│   ├── rio-core          # Agent 引擎、消息类型、对话循环
│   ├── rio-providers     # AI 提供商抽象（Claude/OpenAI/Gemini/DeepSeek）
│   ├── rio-tools         # 8 种内置工具
│   ├── rio-storage       # SQLite 持久化层
│   ├── rio-security      # 命令风险分类、路径验证
│   ├── rio-cli           # 命令行接口
│   ├── rio-identity      # Agent 角色系统
│   ├── rio-router        # A2A 路由、@mention 解析
│   └── rio-memory        # 共享内存（Evidence/Lessons/Decisions）
└── rio-agent-ui/         # Tauri GUI (Svelte 5 + TailwindCSS)
```

### 技术栈

| 层级 | 技术 |
|------|------|
| **后端** | Rust 1.75+, Tokio (异步), SQLx (数据库), Reqwest (HTTP) |
| **前端** | Tauri 2.0, Svelte 5, TypeScript, Vite |
| **AI 集成** | 流式 SSE, JSON Schema 工具调用 |
| **存储** | SQLite, OS Keychain |
| **安全** | 命令分级、路径验证、Keyring |

### 执行流程

#### 单 Agent 模式
```
用户输入 → AgentEngine
  ↓
AI Provider (流式)
  ↓
工具调用? 
  ├─ 是 → 执行工具 → 返回结果 → AI Provider（继续）
  └─ 否 → 返回最终响应
```

#### 多 Agent 模式
```
复杂任务 → MultiAgentEngine
  ↓
生成 Agent 实例（Orchestrator/Executor/Reviewer）
  ↓
A2A 消息路由（@mention）
  ↓
并发执行 + 共享内存
  ↓
死锁预防 + 超时保护
  ↓
结果聚合
```

---

## 开发指南

### 项目结构

```bash
# 工作区根目录
/Users/liushunqiu/Desktop/rio-agent

# Rust 代码
crates/*/src/

# Tauri GUI
rio-agent-ui/
  ├── src/                # Svelte 前端
  ├── src-tauri/          # Rust 后端
  └── dist/               # 构建产物
```

### 开发命令

```bash
# 构建所有 crates
cargo build

# 只构建 CLI
cargo build --bin rio-cli

# 运行测试（71 tests）
cargo test

# 检查特定 crate
cargo check -p rio-core

# 格式化代码
cargo fmt

# Lint（零警告要求）
cargo clippy -- -D warnings

# GUI 开发
cd rio-agent-ui
npm run tauri:dev
```

### 添加新工具

1. 在 `crates/rio-tools/src/` 创建新文件
2. 实现 `Tool` trait
3. 在 `register_default_tools()` 中注册

```rust
pub struct MyTool;

#[async_trait]
impl Tool for MyTool {
    fn name(&self) -> &str { "my_tool" }
    fn description(&self) -> &str { "Does something useful" }
    fn parameters(&self) -> serde_json::Value { /* JSON schema */ }
    async fn execute(&self, args: serde_json::Value) -> Result<String> {
        // Implementation
    }
}
```

### 添加新 AI 提供商

1. 在 `crates/rio-providers/src/` 创建新文件
2. 实现 `AIProvider` trait
3. 实现 `send_message()` 和 `stream_message()` 方法

```rust
pub struct MyProvider {
    api_key: String,
    model: String,
}

#[async_trait]
impl AIProvider for MyProvider {
    async fn send_message(&self, messages: &[Message], tools: Option<Vec<Value>>) 
        -> Result<Message> { /* ... */ }
    
    async fn stream_message(&self, messages: &[Message], tools: Option<Vec<Value>>) 
        -> Result<Receiver<Result<StreamChunk>>> { /* ... */ }
    
    fn model_name(&self) -> &str { &self.model }
}
```

### 测试策略

```bash
# 运行所有测试
cargo test

# 特定模块测试
cargo test -p rio-security
cargo test -p rio-router
cargo test -p rio-memory

# 显示输出
cargo test -- --nocapture
```

**测试覆盖**（71 tests）:
- rio-security: 8 tests (命令分类)
- rio-router: 31 tests (@mention 解析 + A2A 路由)
- rio-memory: 26 tests (Evidence/Lessons/Decisions)
- rio-identity: 4 tests (角色和能力)
- rio-core: 2 tests (基础功能)

---

## 许可证

MIT License

---

## 致谢

架构灵感来源：
- [Clowder AI](https://github.com/pico-rb/clowder-ai) - 多 Agent 协作设计
- [Anthropic Claude](https://anthropic.com) - AI 能力支持

---

**构建状态**: ✅ 所有测试通过 · ✅ 零 Clippy 警告 · ✅ Tauri GUI 可运行

最后更新: 2026-06-21
