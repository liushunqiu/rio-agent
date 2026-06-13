# AGENT.md
本文件为 Rio Agent 提供项目上下文信息。

## 项目概述

Rio Agent 是一个 macOS 原生 AI Agent 应用，类似 OpenAI Codex CLI，使用 Swift 5.9+ 和 SwiftUI 构建。

- **平台要求**: macOS 14.0+
- **构建系统**: Swift Package Manager + Xcode 项目（xcodegen 生成）
- **AI 服务**: 支持 Claude 和 OpenAI API，通过流式 SSE 响应处理

## 构建与运行

```bash
# Xcode 开发（推荐，支持断点调试）
open RioAgent.xcodeproj

# Swift Package Manager 构建
swift build
swift run

# 运行测试
swift test

# 创建 macOS 应用包
./create_app.sh

# 使用构建脚本
./build.sh build
./build.sh run
```

## Xcode 项目管理

Xcode 项目由 xcodegen 从 `project.yml` 自动生成：

```bash
# 安装 xcodegen（如未安装）
brew install xcodegen

# 修改 project.yml 后重新生成项目
xcodegen generate
```

不要直接修改 `RioAgent.xcodeproj`，所有项目配置变更应在 `project.yml` 中进行。

## 项目架构

```
rio-agent/
├── RioAgent.xcodeproj   # Xcode 项目（xcodegen 生成，勿手动修改）
├── project.yml           # xcodegen 配置
├── Package.swift         # SPM 配置
├── Info.plist            # 应用配置
├── Agent/                # Agent 引擎核心
│   ├── AgentEngine.swift       # 单 Agent 对话引擎，处理工具调用循环
│   ├── MultiAgentEngine.swift  # 多 Agent 协作引擎
│   ├── AgentMemory.swift       # Agent 记忆系统
│   ├── ContextAwareness.swift  # 上下文感知
│   ├── ConversationManager.swift # 对话管理
│   ├── IntelligentAssistantConfig.swift # 智能助手配置
│   ├── IntelligentCodeAnalyzer.swift    # 智能代码分析
│   ├── IntelligentLearningSystem.swift  # 智能学习系统
│   └── TaskPlanner.swift       # 任务规划
├── Services/             # AI API 服务层
│   ├── AIService.swift         # 服务协议定义和工厂类
│   ├── ClaudeService.swift     # Claude API 实现
│   └── OpenAIService.swift     # OpenAI/兼容 API 实现
├── Tools/                # 工具系统（Tool 协议 + 具体实现）
│   ├── ToolProtocol.swift      # 工具协议、CommandClassifier、风险等级分类
│   ├── ToolRegistry.swift      # 工具注册中心
│   ├── ToolRecommender.swift   # 工具推荐
│   ├── ShellTool.swift         # Shell 命令执行
│   ├── FileReadTool.swift      # 文件读取
│   ├── FileWriteTool.swift     # 文件写入
│   ├── EditFileTool.swift      # 文件编辑
│   ├── ApplyPatchTool.swift    # 补丁应用
│   ├── FindFilesTool.swift     # 文件查找
│   ├── SearchFilesTool.swift   # 文件搜索
│   └── ListDirectoryTool.swift # 目录列表
├── Models/               # 数据模型（Message, Conversation, ToolCall）
├── Views/                # SwiftUI 界面组件
├── ViewModels/           # 视图模型
├── Utils/                # 工具类（ProcessRunner, PermissionManager）
└── Theme/                # 主题配置
```

## 工具系统设计

工具通过 `Tool` 协议定义，需实现 `name`、`description`、`parameters` 属性和 `execute` 方法。

命令风险分类（`CommandClassifier.classify()`）：
- **safe**: ls, cat, grep, git status/log/diff 等只读命令 -> 自动执行
- **normal**: 大多数命令 -> 需要用户确认
- **dangerous**: rm, sudo, curl, wget, kill -9 等 -> 始终需要确认

添加新工具：
1. 在 `Tools/` 创建实现 `Tool` 协议的类
2. 在 `ToolRegistry` 中注册

## 非显而易见的注意事项

- **Xcode 项目是生成的**: `RioAgent.xcodeproj` 由 xcodegen 从 `project.yml` 生成，不要手动修改；新增文件后运行 `xcodegen generate`
- **Info.plist 嵌入**: SPM 方式使用 linker flags 将 Info.plist 嵌入二进制文件（见 Package.swift 的 `linkerSettings`）
- **NSAllowsArbitraryLoads**: Info.plist 允许任意网络请求（开发阶段）
- **API Key 存储**: 存储在 UserDefaults 中
- **流式响应**: 使用 SSE（Server-Sent Events）格式解析 AI 响应
- **确认机制**: 所有非安全命令都需要用户通过 `ConfirmationCallback` 确认
