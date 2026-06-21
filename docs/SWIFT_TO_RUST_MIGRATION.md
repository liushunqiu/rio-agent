# Swift 到 Rust 迁移计划

## 当前状态分析

### 代码库现状
- **Swift 代码**: 153 个文件（macOS 原生 GUI + 业务逻辑）
- **Rust 代码**: 25 个文件，4276 行（跨平台核心）
- **架构阶段**: 从 Swift 单端转向 Rust 多端

### 功能模块对比

| 功能 | Swift 实现 | Rust 实现 | 迁移状态 |
|------|-----------|----------|---------|
| **AI Provider** | `Services/AIService.swift` | `rio-providers` ✅ | 已完成 |
| **工具系统** | `Tools/*.swift` (14 个文件) | `rio-tools` ✅ | 已完成 |
| **存储层** | `Models/ConfigSet.swift` | `rio-storage` ✅ | 已完成 |
| **Agent 引擎** | `Agent/AgentEngine.swift` | `rio-core` ✅ | 已完成 |
| **多 Agent** | ❌ 无 | `rio-identity/router/memory` ✅ | 新增功能 |
| **CLI** | ❌ 无 | `rio-cli` ✅ | 新增功能 |
| **GUI** | `Views/*.swift` (60+ 文件) | ❌ 未实现 | **待决策** |
| **macOS 集成** | `App/*.swift` (SwiftUI) | ❌ 未实现 | **待决策** |

### Rust 已实现的核心能力

✅ **Phase 1**: 单 Agent 基础架构
- AI Provider 抽象 (Claude/OpenAI/Gemini/DeepSeek)
- 8 个工具 (命令执行、文件操作、搜索)
- 安全层 (命令分类、路径验证)
- SQLite 持久化

✅ **Phase 3**: 多 Agent 协作
- Agent 身份管理 (rio-identity)
- Agent 间路由 (@mention, A2A Router)
- 共享内存 (Evidence/Lessons/Decisions)
- MultiAgentEngine 编排

### Swift 剩余功能

🔶 **GUI 层** (Views/*)
- 60+ SwiftUI 视图文件
- 聊天界面、设置界面、Markdown 渲染
- 文件选择器、侧边栏、工具调用可视化

🔶 **macOS 平台特性**
- Keychain 集成
- 系统通知
- 窗口管理
- Dark Mode 主题

## 迁移策略选项

### 选项 1: 完全移除 Swift，纯 CLI/TUI
**适合场景**: 专注跨平台 CLI 工具

**优势**:
- 100% 跨平台 (macOS/Windows/Linux)
- 统一代码库，降低维护成本
- 专注终端用户

**劣势**:
- 失去原生 macOS GUI 体验
- 用户需要适应命令行界面

**实施步骤**:
1. 删除所有 Swift 文件
2. 增强 rio-cli (交互式 TUI)
3. 使用 ratatui 构建终端 UI
4. 文档迁移到 Rust

### 选项 2: 保留 Swift GUI 作为 macOS 前端
**适合场景**: macOS 用户占主体，需要原生体验

**架构**:
```
┌──────────────────┐
│  SwiftUI (macOS) │  ← 仅 UI 层
└────────┬─────────┘
         │ FFI (C ABI)
┌────────▼─────────┐
│   Rust Core      │  ← 业务逻辑
│  (跨平台)        │
└──────────────────┘
```

**优势**:
- 保留原生 macOS 体验
- Rust 核心复用于 Windows/Linux CLI
- 渐进式迁移

**劣势**:
- 需要维护两套 UI (Swift GUI + CLI)
- FFI 绑定复杂性

**实施步骤**:
1. 移除 Swift 业务逻辑（已被 Rust 替代）
2. 保留 SwiftUI 视图层
3. 实现 Rust → Swift FFI 绑定
4. Swift 调用 Rust 核心

### 选项 3: Web 前端 + Tauri
**适合场景**: 想要跨平台 GUI + 一致体验

**架构**:
```
┌──────────────────┐
│  Web UI (Svelte) │  ← 跨平台 UI
└────────┬─────────┘
         │ Tauri Bridge
┌────────▼─────────┐
│   Rust Core      │  ← 业务逻辑
└──────────────────┘
```

**优势**:
- 完全跨平台 GUI (macOS/Windows/Linux)
- 单一 UI 代码库
- 现代 Web 技术栈

**劣势**:
- 需要重写整个 UI（从 SwiftUI 到 Web）
- 性能不如原生

## 推荐方案

基于你的需求（"适配多端"），我推荐：

### **阶段 1: 立即执行（1-2 周）**
✅ 删除 Swift 业务逻辑层（已被 Rust 完全替代）
- `Agent/AgentEngine.swift`
- `Agent/TaskPlanner.swift`
- `Tools/*.swift`（工具实现）
- `Services/AIService.swift`（Provider 层）

保留 Swift UI 层作为临时遗留

### **阶段 2: GUI 决策（需要你决定）**
🔶 **选择一条路**:
- **路线 A**: 完全移除 Swift，专注 CLI/TUI（推荐用于开发者工具）
- **路线 B**: Swift GUI + Rust Core FFI（推荐用于 macOS 主力用户）
- **路线 C**: Tauri Web GUI（推荐用于跨平台 GUI 需求）

### **阶段 3: 文档清理**
- 更新 CLAUDE.md（标记 Swift 为遗留）
- 更新 README.md（Rust 为主要入口）
- 更新构建脚本（移除 Xcode 依赖）

## 立即行动项

我建议现在先做决策：

**你更倾向于哪个方向？**
1. **纯 CLI/TUI** - 删除所有 Swift，专注终端
2. **Swift GUI 保留** - FFI 绑定 Rust 核心
3. **Tauri Web** - 重写 UI 为 Web

确定方向后，我会立即开始执行对应的迁移步骤。
