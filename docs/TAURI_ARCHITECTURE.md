# Tauri GUI 架构设计

## 概览

Rio Agent 的 GUI 层基于 Tauri 2.0 + Svelte 5 构建，实现跨平台桌面应用（macOS/Windows/Linux）。

## 技术栈选择

### 前端
- **框架**: Svelte 5 (runes API)
- **理由**: 
  - 编译时优化，运行时性能最优
  - 响应式语法简洁（`$state`, `$derived`, `$effect`）
  - 包体积小（~5KB runtime）
  - 学习曲线平缓

### 后端
- **Tauri 2.0**: Rust 原生后端
- **集成**: 复用现有 9 个 crates（rio-core, rio-providers, rio-tools 等）

### UI 库
- **TailwindCSS**: 实用优先的 CSS 框架
- **shadcn-svelte**: 高质量 UI 组件库（Radix Svelte port）
- **lucide-svelte**: 图标库

## 架构层级

```
┌─────────────────────────────────────────────────────────┐
│                    Svelte Frontend                       │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │  Chat View   │  │ Settings View│  │ Sidebar View │  │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘  │
│         │                 │                 │           │
│         └─────────────────┼─────────────────┘           │
│                           │                             │
│                  ┌────────▼────────┐                    │
│                  │  Tauri Commands │                    │
│                  │   (invoke API)  │                    │
└──────────────────┴─────────────────┴────────────────────┘
                           │
                           │ IPC
                           │
┌──────────────────────────▼──────────────────────────────┐
│                    Tauri Backend (Rust)                  │
│  ┌──────────────────────────────────────────────────┐   │
│  │            Command Handlers                      │   │
│  │  - send_message()                                │   │
│  │  - list_conversations()                          │   │
│  │  - save_config()                                 │   │
│  │  - execute_tool()                                │   │
│  └────────────────────┬─────────────────────────────┘   │
│                       │                                  │
│  ┌────────────────────▼─────────────────────────────┐   │
│  │          Rio Core Crates                         │   │
│  │  - AgentEngine (rio-core)                        │   │
│  │  - AIProvider (rio-providers)                    │   │
│  │  - ToolRegistry (rio-tools)                      │   │
│  │  - SqliteStorage (rio-storage)                   │   │
│  │  - SharedMemory (rio-memory)                     │   │
│  └──────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────┘
```

## 前端架构

### 目录结构

```
src-ui/                          # Svelte 前端代码
├── lib/
│   ├── components/
│   │   ├── chat/
│   │   │   ├── MessageBubble.svelte
│   │   │   ├── ChatInput.svelte
│   │   │   ├── ToolCallCard.svelte
│   │   │   └── StreamingIndicator.svelte
│   │   ├── sidebar/
│   │   │   ├── ConversationList.svelte
│   │   │   └── ConversationItem.svelte
│   │   ├── settings/
│   │   │   ├── ModelSettings.svelte
│   │   │   ├── ApiKeyManager.svelte
│   │   │   └── MultiAgentSettings.svelte
│   │   └── shared/
│   │       ├── Button.svelte
│   │       ├── Input.svelte
│   │       └── Modal.svelte
│   ├── stores/
│   │   ├── conversation.svelte.ts    # 对话状态 ($state)
│   │   ├── config.svelte.ts          # 配置状态
│   │   └── ui.svelte.ts              # UI 状态（侧边栏展开等）
│   ├── api/
│   │   ├── tauri.ts                  # Tauri invoke 封装
│   │   └── types.ts                  # TypeScript 类型定义
│   └── utils/
│       ├── markdown.ts               # Markdown 渲染
│       └── streaming.ts              # SSE 流处理
├── routes/
│   ├── +layout.svelte                # 全局布局
│   ├── +page.svelte                  # 聊天主页
│   └── settings/+page.svelte         # 设置页
└── app.css                           # Tailwind 入口
```

### 状态管理

使用 Svelte 5 的 runes API 进行状态管理：

```typescript
// lib/stores/conversation.svelte.ts
import { invoke } from '@tauri-apps/api/core';

interface Message {
  id: string;
  role: 'user' | 'assistant';
  content: string;
  toolCalls?: ToolCall[];
  timestamp: number;
}

class ConversationStore {
  conversations = $state<Conversation[]>([]);
  currentId = $state<string | null>(null);
  
  get current() {
    return $derived(
      this.conversations.find(c => c.id === this.currentId)
    );
  }
  
  async sendMessage(content: string) {
    const result = await invoke('send_message', { 
      conversationId: this.currentId,
      content 
    });
    // Update state...
  }
}

export const conversationStore = new ConversationStore();
```

## 后端架构

### Tauri Crate 结构

```
crates/
└── rio-tauri/                   # 新增：Tauri 应用 crate
    ├── src/
    │   ├── main.rs              # Tauri 入口
    │   ├── commands/
    │   │   ├── mod.rs           # 命令模块导出
    │   │   ├── conversation.rs  # 对话相关命令
    │   │   ├── config.rs        # 配置相关命令
    │   │   └── tools.rs         # 工具相关命令
    │   ├── state.rs             # 全局状态管理
    │   └── events.rs            # 事件发射
    └── Cargo.toml
```

### Tauri Commands

#### 1. 对话管理

```rust
// commands/conversation.rs
use tauri::{State, Window};
use rio_core::{AgentEngine, Message, Role};

#[tauri::command]
async fn send_message(
    conversation_id: String,
    content: String,
    state: State<'_, AppState>,
    window: Window,
) -> Result<String, String> {
    let engine = state.get_engine(&conversation_id)?;
    
    // 流式输出
    let mut stream = engine.process_message_streaming(&content).await?;
    
    while let Some(chunk) = stream.next().await {
        window.emit("message_chunk", chunk)?;
    }
    
    Ok("Message sent".to_string())
}

#[tauri::command]
async fn list_conversations(
    state: State<'_, AppState>,
) -> Result<Vec<ConversationInfo>, String> {
    state.storage.list_conversations().await
        .map_err(|e| e.to_string())
}

#[tauri::command]
async fn create_conversation(
    state: State<'_, AppState>,
) -> Result<String, String> {
    let id = uuid::Uuid::new_v4().to_string();
    state.storage.create_conversation(&id).await?;
    Ok(id)
}
```

#### 2. 配置管理

```rust
// commands/config.rs
use rio_storage::ConfigSet;

#[tauri::command]
async fn save_api_key(
    provider: String,
    api_key: String,
    state: State<'_, AppState>,
) -> Result<(), String> {
    state.storage.save_config(&provider, &api_key).await
        .map_err(|e| e.to_string())
}

#[tauri::command]
async fn list_configs(
    state: State<'_, AppState>,
) -> Result<Vec<ConfigSet>, String> {
    state.storage.list_configs().await
        .map_err(|e| e.to_string())
}
```

#### 3. 工具执行

```rust
// commands/tools.rs
use rio_tools::ToolRegistry;

#[tauri::command]
async fn list_tools(
    state: State<'_, AppState>,
) -> Result<Vec<ToolInfo>, String> {
    let registry = &state.tool_registry;
    Ok(registry.list_tools())
}

#[tauri::command]
async fn execute_tool(
    tool_name: String,
    args: serde_json::Value,
    state: State<'_, AppState>,
) -> Result<String, String> {
    let registry = &state.tool_registry;
    registry.execute(&tool_name, args).await
        .map_err(|e| e.to_string())
}
```

### 全局状态

```rust
// state.rs
use std::sync::Arc;
use tokio::sync::RwLock;
use rio_core::AgentEngine;
use rio_storage::SqliteStorage;
use rio_tools::ToolRegistry;

pub struct AppState {
    pub storage: Arc<SqliteStorage>,
    pub tool_registry: Arc<ToolRegistry>,
    pub engines: Arc<RwLock<HashMap<String, AgentEngine>>>,
}

impl AppState {
    pub async fn new() -> anyhow::Result<Self> {
        let storage = Arc::new(SqliteStorage::new("sqlite:rio.db").await?);
        let tool_registry = Arc::new(ToolRegistry::new());
        let engines = Arc::new(RwLock::new(HashMap::new()));
        
        Ok(Self {
            storage,
            tool_registry,
            engines,
        })
    }
    
    pub async fn get_engine(&self, conversation_id: &str) -> anyhow::Result<AgentEngine> {
        let mut engines = self.engines.write().await;
        if let Some(engine) = engines.get(conversation_id) {
            return Ok(engine.clone());
        }
        
        // 创建新引擎
        let config = self.storage.get_config().await?;
        let provider = create_provider(&config)?;
        let engine = AgentEngine::new(provider, self.tool_registry.clone());
        engines.insert(conversation_id.to_string(), engine.clone());
        Ok(engine)
    }
}
```

## 流式消息传输

### 前端监听事件

```typescript
// lib/api/tauri.ts
import { listen } from '@tauri-apps/api/event';

export async function sendMessageStreaming(
  conversationId: string,
  content: string,
  onChunk: (chunk: string) => void
) {
  const unlisten = await listen('message_chunk', (event) => {
    onChunk(event.payload as string);
  });
  
  try {
    await invoke('send_message', { conversationId, content });
  } finally {
    unlisten();
  }
}
```

### 后端发射事件

```rust
// commands/conversation.rs
async fn send_message(
    window: Window,
    // ...
) -> Result<String, String> {
    let mut stream = engine.process_message_streaming(&content).await?;
    
    while let Some(chunk) = stream.next().await {
        window.emit("message_chunk", MessageChunk {
            conversation_id: conversation_id.clone(),
            content: chunk,
        })?;
    }
    
    Ok("done".to_string())
}
```

## UI 设计原则

参考项目的 `<design_sense>` 指导：

1. **配色方案**:
   - 背景: `#F7F5F1` (柔和米白)
   - 表面: `#FFFFFF`
   - 边框: `#E7E3DA`
   - 文字: `#1E2227`
   - 强调色: `#3C5A78` (石板蓝)

2. **排版**:
   - 标题: Playfair Display (serif)
   - 正文/UI: Inter

3. **布局**:
   - 三栏布局: 侧边栏 (240px) | 聊天主区域 | 右侧面板 (可选)
   - 圆角: `8px`
   - 间距: `16px/24px/32px`

## 数据持久化

### 对话历史
- 存储位置: SQLite (`~/.rio-agent/conversations.db`)
- 表结构:
  ```sql
  CREATE TABLE conversations (
      id TEXT PRIMARY KEY,
      title TEXT,
      created_at TEXT,
      updated_at TEXT
  );
  
  CREATE TABLE messages (
      id TEXT PRIMARY KEY,
      conversation_id TEXT,
      role TEXT,
      content TEXT,
      tool_calls TEXT,  -- JSON
      timestamp TEXT,
      FOREIGN KEY (conversation_id) REFERENCES conversations(id)
  );
  ```

### 配置存储
- API Keys: OS Keychain (via `keyring` crate)
- 元数据: SQLite

## 开发计划

### Phase 1: 基础设置 (1-2 天)
- [ ] 初始化 Tauri 项目
- [ ] 配置 Svelte + TailwindCSS
- [ ] 创建 `rio-tauri` crate
- [ ] 实现基础 Tauri commands

### Phase 2: 核心功能 (3-4 天)
- [ ] 实现对话界面
- [ ] 实现流式消息传输
- [ ] 工具调用可视化
- [ ] 对话历史侧边栏

### Phase 3: 配置管理 (2-3 天)
- [ ] 设置面板
- [ ] API Key 管理
- [ ] 模型选择器

### Phase 4: 高级功能 (3-5 天)
- [ ] 多 Agent 模式 UI
- [ ] Markdown 渲染 (代码高亮、表格)
- [ ] 文件上传/附件
- [ ] 主题切换

## 技术风险与缓解

| 风险 | 影响 | 缓解策略 |
|------|------|---------|
| Tauri 2.0 文档不完善 | 开发效率 | 参考官方示例，必要时查看源码 |
| 流式传输性能 | 用户体验 | 使用 debounce，批量更新 DOM |
| 跨平台兼容性 | 功能差异 | 优先实现 macOS，逐步适配 Windows/Linux |
| 打包体积过大 | 分发成本 | Tree-shaking，按需加载组件 |

## 参考资料

- [Tauri 2.0 文档](https://v2.tauri.app/)
- [Svelte 5 文档](https://svelte-5-preview.vercel.app/)
- [shadcn-svelte](https://www.shadcn-svelte.com/)
