# Rio Agent

一个 macOS 原生 AI Agent 应用，类似 OpenAI Codex CLI，使用 Swift 5.9+ 和 SwiftUI 构建。支持多 AI 提供商、工具调用、多 Agent 协作、智能任务规划等能力。

## 功能特性

- **多 AI 支持**：Claude API、OpenAI API 及兼容 API
- **多 Agent 协作**：Orchestrator + Specialist 架构，自动分解复杂任务
- **智能任务规划**：自动分析任务复杂度，生成执行计划
- **项目理解**：自动识别项目类型、架构、依赖关系
- **Agent 记忆系统**：短期会话记忆 + 长期偏好学习
- **工具调用**：Shell 命令、文件读写、编辑、搜索、补丁应用等
- **安全确认**：三级命令风险分类（safe / normal / dangerous）
- **对话管理**：多会话支持，历史自动保存
- **原生体验**：macOS 原生应用，支持暗黑模式、Markdown 渲染

## 系统要求

- macOS 14.0+
- Xcode 15.0+
- Swift 5.9+

## 快速开始

### 克隆项目

```bash
git clone <repository-url>
cd rio-agent
```

### Xcode 开发（推荐）

```bash
open RioAgent.xcodeproj
```

在 Xcode 中按 `⌘R` 构建运行，支持断点调试和 Debug Console。

### 命令行构建与运行

```bash
swift build
swift run
```

### 创建 macOS 应用包

```bash
./create_app.sh
```

生成的 `Rio Agent.app` 可直接运行或拖入 Applications 文件夹。

### 运行测试

```bash
swift test
```

## 配置 API Key

1. 启动应用，点击右上角齿轮图标打开设置
2. 选择 AI 提供商（Claude 或 OpenAI）
3. 输入 API Key，支持自定义 Base URL
4. 点击"完成"保存

## 项目架构

```
rio-agent/
├── RioAgent.xcodeproj       # Xcode 项目（xcodegen 生成，勿手动修改）
├── project.yml               # xcodegen 配置
├── Package.swift             # Swift Package Manager 配置
├── Info.plist                # 应用配置
├── Agent/                    # Agent 引擎核心
│   ├── AgentEngine.swift           # 单 Agent 对话引擎
│   ├── MultiAgentEngine.swift      # 多 Agent 协作引擎
│   ├── AgentMemory.swift           # 记忆系统（短期 + 长期）
│   ├── TaskPlanner.swift           # 智能任务规划器
│   ├── ProjectAnalyzer.swift       # 项目结构分析器
│   ├── ConversationManager.swift   # 对话管理
│   ├── CodeNavigator.swift         # 代码导航
│   ├── MultiFileCoordinator.swift  # 多文件协调器
│   └── RefactoringAdvisor.swift    # 重构建议
├── Services/                 # AI API 服务层
│   ├── AIService.swift             # 服务协议 + 工厂类
│   ├── ClaudeService.swift         # Claude API（流式 SSE）
│   └── OpenAIService.swift         # OpenAI / 兼容 API
├── Tools/                    # 工具系统
│   ├── ToolProtocol.swift          # Tool 协议、CommandClassifier
│   ├── ToolRegistry.swift          # 工具注册中心
│   ├── ToolRecommender.swift       # 工具智能推荐
│   ├── ShellTool.swift             # Shell 命令执行
│   ├── FileReadTool.swift          # 文件读取
│   ├── FileWriteTool.swift         # 文件写入
│   ├── EditFileTool.swift          # 文件编辑
│   ├── ApplyPatchTool.swift        # 补丁应用
│   ├── FindFilesTool.swift         # 文件查找
│   ├── SearchFilesTool.swift       # 文件内容搜索
│   └── ListDirectoryTool.swift     # 目录列表
├── Models/                   # 数据模型
│   ├── Message.swift               # 消息模型
│   ├── Conversation.swift          # 会话模型
│   ├── ToolCall.swift              # 工具调用模型
│   ├── ModelCapabilities.swift     # 模型能力定义
│   └── MultiAgentConfig.swift      # 多 Agent 配置
├── Views/                    # SwiftUI 界面组件
│   ├── ContentView.swift           # 主界面
│   ├── NewChatPage.swift           # 新建对话页
│   ├── SettingsView.swift          # 设置页
│   ├── MultiAgentSettingsView.swift # 多 Agent 设置
│   ├── EnhancedMessageBubble.swift  # 消息气泡
│   ├── EnhancedToolCallCard.swift   # 工具调用卡片
│   ├── MarkdownRenderer.swift      # Markdown 渲染器
│   ├── TaskPlanView.swift          # 任务计划视图
│   └── ...
├── ViewModels/               # 视图模型
├── Utils/                    # 工具类
│   ├── ProcessRunner.swift         # 进程运行器
│   ├── PermissionManager.swift     # 权限管理
│   ├── KeychainManager.swift       # Keychain 安全存储
│   ├── PathSecurity.swift          # 路径安全检查
│   └── Logger.swift                # 日志工具
├── Theme/                    # 主题配置
└── Tests/                    # 单元测试
    ├── SafetyRegressionTests.swift  # 安全回归测试
    ├── ModelCapabilitiesTests.swift # 模型能力测试
    └── KeychainManagerTests.swift   # Keychain 测试
```

## 支持的工具

| 工具 | 描述 |
|------|------|
| `execute_command` | 执行 shell 命令 |
| `read_file` | 读取文件内容 |
| `write_file` | 写入文件内容 |
| `edit_file` | 编辑文件（基于文本匹配） |
| `apply_patch` | 应用 unified diff 补丁 |
| `search_files` | 搜索文件内容（正则支持） |
| `find_files` | 按名称模式查找文件 |
| `list_directory` | 列出目录内容 |

## 安全特性

### 命令风险分类

通过 `CommandClassifier.classify()` 自动分级：

- **safe**：只读命令（ls, cat, grep, git status 等）→ 自动执行
- **normal**：大多数命令 → 需要用户确认
- **dangerous**：危险命令（rm, sudo, curl, wget 等）→ 始终需要确认

### 安全机制

- 严格确认模式：所有非安全命令需用户明确确认
- 路径安全检查：防止目录遍历攻击
- Keychain 安全存储敏感信息
- 流式 SSE 响应解析

## 开发指南

### 添加新工具

1. 在 `Tools/` 目录创建新类，实现 `Tool` 协议
2. 在 `ToolRegistry` 中注册

### 添加新 AI 服务

1. 在 `Services/` 目录创建新类，实现 `AIService` 协议
2. 在 `AIServiceFactory` 中添加新提供商

### 更新 Xcode 项目

通过命令行新增 Swift 文件后：

```bash
xcodegen generate
```

或在 Xcode 中右键项目 → Add Files to "RioAgent"。

## 构建方式

| 方式 | 用途 | 说明 |
|------|------|------|
| `open RioAgent.xcodeproj` | Xcode 开发调试 | 支持断点、Debug Console、UI 预览 |
| `swift build` / `swift run` | 命令行快速构建 | 生成命令行可执行文件 |
| `./create_app.sh` | 打包 .app | 生成独立 macOS 应用包 |
| `./build.sh build` | 构建脚本 | 封装常用构建命令 |

## 注意事项

- Xcode 项目由 xcodegen 从 `project.yml` 生成，不要手动修改 `.xcodeproj`
- Info.plist 使用 linker flags 嵌入二进制文件（SPM 方式）
- 开发阶段允许任意网络请求（NSAllowsArbitraryLoads）
- API Key 支持 UserDefaults 和 Keychain 两种存储方式

## 许可证

MIT License
