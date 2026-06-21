# Rio Agent - Rust/Tauri 重构项目

## 项目概述

Rio Agent 的跨平台重构项目，使用 Rust + Tauri 实现真正的跨平台支持（macOS、Windows、Linux，未来支持移动端）。

## 当前状态：Phase 1 完成 ✅

### 已实现功能

- ✅ **Cargo Workspace 架构** - 模块化设计，6 个独立 crate
- ✅ **rio-core** - 核心抽象层（Message、Tool trait、AIProvider trait、AgentEngine）
- ✅ **rio-providers** - Claude API 集成（支持流式和非流式）
- ✅ **rio-tools** - 4 个基础工具（read_file、write_file、list_directory、execute_command）
- ✅ **rio-storage** - SQLite 会话持久化
- ✅ **rio-security** - 跨平台命令风险分级（Safe/Normal/Dangerous）
- ✅ **rio-cli** - 命令行界面（chat、sessions、config 子命令）
- ✅ **跨平台支持** - 代码可在 macOS/Windows/Linux 编译运行
- ✅ **CI/CD** - GitHub Actions 多平台自动测试和构建

### 快速开始

**Unix/Linux/macOS:**
```bash
./quickstart.sh
```

**Windows:**
```cmd
quickstart.bat
```

**手动步骤:**
```bash
# 1. 设置 API Key
export ANTHROPIC_API_KEY=sk-ant-...

# 2. 构建
cargo build --release --bin rio-cli

# 3. 运行
./target/release/rio-cli chat "List files in current directory"
```

## 架构设计

### 模块划分

```
rio-agent/
├── crates/
│   ├── rio-core/          # 核心抽象（与具体实现解耦）
│   │   ├── message.rs     # Message, Role, ToolCall 数据结构
│   │   ├── tool.rs        # Tool trait + ToolRegistry
│   │   ├── provider.rs    # AIProvider trait
│   │   └── agent.rs       # AgentEngine（单 Agent 执行循环）
│   │
│   ├── rio-providers/     # AI 服务提供商实现
│   │   └── claude.rs      # Anthropic Claude API（SSE 流式支持）
│   │
│   ├── rio-tools/         # 工具实现
│   │   ├── file.rs        # read_file, write_file, list_directory
│   │   └── command.rs     # execute_command（跨平台 shell）
│   │
│   ├── rio-storage/       # 数据持久化
│   │   └── lib.rs         # SQLite 会话和消息管理
│   │
│   ├── rio-security/      # 安全层
│   │   └── lib.rs         # CommandClassifier（命令风险分析）
│   │
│   └── rio-cli/           # CLI 入口
│       └── main.rs        # clap 命令行解析 + 主逻辑
│
├── .github/workflows/
│   └── ci.yml             # 多平台 CI/CD
│
├── Cargo.toml             # Workspace 配置
├── quickstart.sh          # Unix 快速启动
└── quickstart.bat         # Windows 快速启动
```

### 核心设计模式

#### 1. AgentEngine 执行循环

```rust
AgentEngine::run(messages) {
    loop {
        response = provider.send_message(messages, tools_schema)
        
        if response.has_tool_calls() {
            for tool_call in response.tool_calls {
                result = tools.get(tool_call.name).execute(tool_call.args)
                messages.push(tool_result)
            }
        } else {
            return response  // 完成
        }
    }
}
```

#### 2. 跨平台命令执行

```rust
#[cfg(unix)]
Command::new("sh").arg("-c").arg(cmd)

#[cfg(windows)]
Command::new("powershell").arg("-Command").arg(cmd)
```

#### 3. 命令风险分级

```rust
CommandClassifier::classify(cmd) -> RiskLevel {
    Safe:      ls, cat, git status, grep
    Normal:    npm, cargo, sed -i
    Dangerous: rm -rf, sudo, curl, kill -9
}
```

## 对比：Swift 版本 vs Rust 版本

| 特性 | Swift (原版) | Rust (新版) | 状态 |
|------|--------------|-------------|------|
| 平台支持 | macOS only | macOS/Win/Linux | ✅ |
| 包体积 | ~5MB | ~8-12MB (预估) | ✅ |
| 内存安全 | ARC | 所有权系统 | ✅ |
| 依赖管理 | 零依赖 | Cargo 生态 | ✅ |
| 单 Agent | ✅ | ✅ | ✅ |
| 多 Agent DAG | ✅ | ❌ (Phase 3) | 🔜 |
| TaskPlanner | ✅ | ❌ (Phase 3) | 🔜 |
| CriticService | ✅ | ❌ (Phase 3) | 🔜 |
| RouterService | ✅ | ❌ (Phase 3) | 🔜 |
| 8 个工具 | ✅ | ✅ (4/8) | ⚠️ |
| GUI | SwiftUI | ❌ (Phase 2 Tauri) | 🔜 |

## 下一步计划

### Phase 2: Tauri Desktop UI (2-3 周)

**目标：** 构建跨平台桌面 GUI

```
rio-agent/
├── src-tauri/           # Tauri 后端（Rust）
│   ├── main.rs          # Tauri 入口
│   └── commands.rs      # Tauri commands（前后端通信）
│
└── src/                 # 前端（React + TypeScript）
    ├── App.tsx
    ├── components/
    │   ├── ChatArea.tsx
    │   ├── SessionList.tsx
    │   └── ToolCallCard.tsx
    └── store/
        └── chatStore.ts
```

**技术栈：**
- 后端：Tauri + rio-core/providers/tools/storage
- 前端：React 19 + TypeScript + Tailwind CSS
- 通信：Tauri IPC (invoke/emit)

**UI 设计：**
```
┌──────────────────────────────────────────────┐
│  Rio Agent          [Settings] [Profile]     │
├─────────┬────────────────────────────────────┤
│ Session │ Chat Area                          │
│ List    │ ┌────────────────────────────────┐ │
│         │ │ User: List files               │ │
│ + New   │ └────────────────────────────────┘ │
│         │ ┌────────────────────────────────┐ │
│ Chat 1  │ │ Assistant:                     │ │
│ Chat 2  │ │ [Tool: list_directory] .       │ │
│         │ │ Found 10 files...              │ │
│         │ └────────────────────────────────┘ │
│         │                                    │
│         │ [Input] Type message... [Send]     │
└─────────┴────────────────────────────────────┘
```

### Phase 3: 智能层 (2-3 周)

**移植 Swift 版本的核心智能组件：**

- [ ] **MultiAgentEngine** - DAG 多 Agent 编排
  - Orchestrator 生成子任务 DAG
  - Worker 并行执行
  - Wave-based 依赖管理
  
- [ ] **TaskPlanner** - 任务复杂度分析
  - Simple/Moderate/Complex/VeryComplex
  - 自动选择单 Agent 或多 Agent
  
- [ ] **CriticService** - 错误分析和自愈
  - PEV (Plan-Execute-Verify) 循环
  - 失败根因分析
  
- [ ] **RouterService** - 智能路由
  - Generic routing (LLM-based)
  - Local routing (small model)

### Phase 4: 差异化功能 (1-2 周)

参考 Clowder AI 设计：

- [ ] **Agent 持久化身份**
  - 角色定义（Orchestrator/Worker/Critic）
  - 性格特征（严谨/创新/稳健）
  - 历史记忆（成功/失败案例）
  
- [ ] **共享知识库**
  - 项目知识（文件结构/依赖/规范）
  - 问题模式（常见错误 + 修复）
  - 最佳实践（团队约定）
  
- [ ] **Skills 框架**
  - Markdown 定义专用能力
  - 动态注入到 System Prompt
  - 用户自定义 Skills
  
- [ ] **SOP Guardian**
  - 代码修改前 → 设计评审
  - 多文件改动 → 影响分析
  - 危险操作 → 二次确认

### Phase 5: 移动端（可选，3-4 周）

**策略：** 移动端作为"伴随端"，不承诺本地全功能 Agent

- [ ] Tauri 移动端适配（Android/iOS）
- [ ] 查看会话历史
- [ ] 配置管理（模型/API Key/Skills）
- [ ] 远程执行（通过桌面端 daemon）

## 技术债务和已知问题

### 当前限制

1. **工具不完整** - 只实现了 4/8 个工具
   - ❌ edit_file
   - ❌ apply_patch
   - ❌ search_files
   - ❌ find_files

2. **流式响应未实现** - `stream_message()` 只是占位符

3. **错误处理简化** - 生产环境需要更细粒度的错误类型

4. **无权限确认机制** - CLI 版本暂时自动执行所有工具调用

### 技术风险

1. **SQLx 编译时检查** - 需要数据库连接，可能影响 CI
   - 解决方案：使用 `DATABASE_URL` 环境变量 + offline mode

2. **Keyring 跨平台** - API Key 存储在不同平台行为不同
   - macOS: Keychain
   - Windows: Credential Manager
   - Linux: Secret Service API / gnome-keyring

3. **Tauri 移动端成熟度** - 2.0 移动端支持仍在快速迭代

## 参考资源

- [Tauri 官方文档](https://v2.tauri.app/)
- [SQLx 文档](https://github.com/launchbadge/sqlx)
- [Clowder AI](https://github.com/zts212653/clowder-ai) - 多 Agent 协作参考
- [Swift 原版 CLAUDE.md](./CLAUDE.md) - 原版架构文档

## 贡献指南

### 开发环境

```bash
# 安装依赖
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# 克隆仓库
git clone https://github.com/yourusername/rio-agent.git
cd rio-agent

# 运行测试
cargo test --workspace

# 运行 CLI
export ANTHROPIC_API_KEY=sk-ant-...
cargo run --bin rio-cli chat "Hello"
```

### 提交规范

- `feat:` 新功能
- `fix:` Bug 修复
- `refactor:` 重构
- `test:` 测试相关
- `docs:` 文档更新

## License

MIT
