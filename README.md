# Rio Agent

macOS 原生 AI 编程助手，使用 Swift 5.9+ 和 SwiftUI 构建。支持多 AI 提供商、8 种内置工具、多 Agent 协作（DAG 波次执行）、智能任务规划、Critic 错误自愈、本地路由器等能力。

## 系统要求

- macOS 14.0+
- Xcode 15.0+
- Swift 5.9+

## 快速开始

```bash
# Xcode 开发（推荐）
open RioAgent.xcodeproj

# 命令行构建
swift build
swift run

# 运行测试
swift test

# 打包 .app
# 有 Team ID 时走稳定签名；否则自动回退到未签名本地模式（不使用 Keychain）
./create_app.sh

# 显式指定稳定签名
RIO_DEVELOPMENT_TEAM=ABCDE12345 ./create_app.sh

# 如只需临时未签名包
./create_app.sh --unsigned

# 构建脚本
./build.sh build    # 构建
./build.sh run      # 构建并运行
./build.sh app      # 构建已签名 .app
./build.sh test     # 运行测试
./build.sh clean    # 清理构建产物
```

## 配置

启动应用后点击右上角齿轮图标打开设置。通过 **ConfigSet** 管理 AI 模型配置：

- 每个 ConfigSet = 一个模型实例（提供商 + Base URL + 模型名 + API Key）
- API Key 存储在 macOS Keychain 中
- 支持三种提供商：Claude（Anthropic）、OpenAI、OpenAI 兼容 API（自定义端点）
- 可为规划模型和执行模型分别指定不同的 ConfigSet

## 核心架构

### 单 Agent 引擎（AgentEngine）

处理简单到中等复杂度任务的默认路径：

1. **路由拦截**：可选的 RouterService 前置判断，跳过闲聊或将任务路由到指定目标
2. **任务分析**：TaskPlanner 评估任务复杂度（simple / moderate / complex / veryComplex）
3. **执行循环**：流式或非流式的 Tool-Call Loop，支持最多 9999 次工具调用迭代
4. **错误自愈**：连续错误时注入 Error Reflection，2 次以上触发 Critic 分析
5. **上下文管理**：智能 Token 估算（区分 ASCII / CJK / 结构化文本），自动压缩旧工具输出

### 多 Agent 引擎（MultiAgentEngine）

处理复杂任务的四层流水线：

| 层级 | 名称 | 职责 |
|------|------|------|
| Layer 2 | Planner | Orchestrator 生成 DAG 子任务图，指定 Worker 和依赖关系 |
| Layer 3 | Execution Guild | 按 DAG 波次并行执行子任务（无依赖的任务并行，有依赖的等待前置完成） |
| Layer 4 | Critic & Verification | PEV（Plan-Execute-Verify）重试循环，Critic 分析失败原因并生成修复建议 |
| Synthesis | Result Synthesis | Orchestrator 汇总所有子任务结果，生成最终回答 |

Worker 类型：`search`（信息检索）、`code`（代码分析）、`file`（文件操作）、`general`（通用）、`custom`（自定义系统提示词）。

### 本地路由器（RouterService）

可选的前置拦截层，支持两种模式：

- **通用路由**：通过配置的 AI 模型判断 skip / process
- **Qwen3.5-4B 路由**：本地小模型结构化输出，支持 `guided_json` 强制 JSON Schema，可路由到 skip / code_expert / search_agent / data_analyst / chitchat / process 等目标节点

## 工具系统

8 个内置工具，通过 `Tool` 协议定义：

| 工具 | 描述 | 风险等级 |
|------|------|----------|
| `execute_command` | 执行 Shell 命令 | 按命令自动分类 |
| `read_file` | 读取文件内容 | safe |
| `write_file` | 写入文件（全量覆盖） | 需确认（工作目录外） |
| `edit_file` | 搜索替换编辑 | 需确认（工作目录外） |
| `apply_patch` | 应用 unified diff 补丁 | 需确认 |
| `search_files` | 正则搜索文件内容 | safe |
| `find_files` | 按名称模式查找文件 | safe |
| `list_directory` | 列出目录内容 | safe |

### 命令风险分类（CommandClassifier）

- **safe**：只读命令（ls, cat, grep, git status/log/diff 等）→ 自动执行
- **normal**：大多数命令 → 需要用户确认
- **dangerous**：危险命令（rm -rf, sudo, curl, wget, kill -9 等）→ 始终需要确认

分类器支持管道命令（`|`）、Shell 控制运算符（`&&`、`||`、`;`）和重定向（`>`、`>>`）的递归分析。

## 智能子系统

| 模块 | 文件 | 职责 |
|------|------|------|
| TaskPlanner | `Agent/TaskPlanner.swift` | 任务复杂度分析、步骤分解、执行指导生成 |
| AgentMemory | `Agent/AgentMemory.swift` | 短期会话记忆 + 长期偏好学习（工具使用模式、错误历史、编码风格） |
| ProjectAnalyzer | `Agent/ProjectAnalyzer.swift` | 自动识别项目类型（iOS/macOS/Web/CLI 等）、框架、依赖、构建系统 |
| CodeNavigator | `Agent/CodeNavigator.swift` | 代码符号提取、定义跳转、引用查找（支持 Swift/JS/Python/Rust/Go） |
| MultiFileCoordinator | `Agent/MultiFileCoordinator.swift` | 文件关系分析（导入/继承/引用/测试）、协调多文件修改 |
| RefactoringAdvisor | `Agent/RefactoringAdvisor.swift` | 代码异味检测（长函数、重复代码、魔法数字、深层嵌套等）、重构建议 |
| ToolRecommender | `Agent/ToolRecommender.swift` | 用户意图分析、工具组合推荐 |
| CriticService | `Agent/CriticService.swift` | 错误分析与修复建议生成（单 Agent 和多 Agent 共用） |

## 内置命令

| 命令 | 描述 |
|------|------|
| `/init` | AI 分析项目结构并生成 AGENT.md 上下文文件 |
| `/clear` | 清除当前对话历史 |
| `/compact` | 压缩对话上下文，节省 Token 消耗 |
| `/export` | 导出当前对话为 Markdown 文件 |
| `/help` | 显示帮助信息 |

## UI 特性

- 暗黑模式原生设计（自定义 Theme 设计系统）
- 流式 Markdown 渲染
- 工具调用过程可视化（状态卡片 + 文件操作动画）
- 多会话管理（侧边栏切换、自动标题生成）
- 任务计划实时展示（TaskPlanView）
- Thinking Content 折叠显示（支持 Claude extended thinking）
- 流式缓冲合并（StreamBuffer，12fps + 500 字符批量刷新，减少 SwiftUI 重绘）

## 项目结构

```
rio-agent/
├── App/                    # 应用入口与全局状态
│   ├── RioAgentApp.swift         # @main 入口，WindowGroup 配置
│   └── AppState.swift            # 全局配置、错误定义、常量
├── Agent/                  # Agent 引擎核心
│   ├── AgentEngine.swift         # 单 Agent 对话引擎（Tool-Call Loop）
│   ├── MultiAgentEngine.swift    # 多 Agent 协作引擎（DAG 波次执行）
│   ├── TaskPlanner.swift         # 任务分析与分解
│   ├── AgentMemory.swift         # 记忆系统（短期 + 长期）
│   ├── ConversationManager.swift # 对话管理（持久化、自动标题）
│   ├── CriticService.swift       # Critic 错误分析
│   ├── ProjectAnalyzer.swift     # 项目结构分析
│   ├── CodeNavigator.swift       # 代码导航
│   ├── MultiFileCoordinator.swift# 多文件协调
│   └── RefactoringAdvisor.swift  # 重构建议
├── Services/               # AI API 服务层
│   ├── AIService.swift           # 协议定义 + 工厂类 + SSE 解析器
│   ├── ClaudeService.swift       # Claude API（Anthropic）
│   ├── OpenAIService.swift       # OpenAI / 兼容 API
│   └── RouterService.swift       # 路由服务（通用 + Qwen3.5-4B）
├── Tools/                  # 工具系统
│   ├── ToolProtocol.swift        # Tool 协议、CommandClassifier、风险分类
│   ├── ToolRegistry.swift        # 工具注册中心
│   ├── ToolRecommender.swift     # 工具智能推荐
│   ├── ShellTool.swift           # Shell 命令执行
│   ├── FileReadTool.swift        # 文件读取
│   ├── FileWriteTool.swift       # 文件写入
│   ├── EditFileTool.swift        # 文件编辑（搜索替换）
│   ├── ApplyPatchTool.swift      # 补丁应用
│   ├── FindFilesTool.swift       # 文件查找
│   ├── SearchFilesTool.swift     # 文件内容搜索
│   └── ListDirectoryTool.swift   # 目录列表
├── Models/                 # 数据模型
│   ├── Message.swift             # 消息模型（支持 thinking/toolCalls/toolResults/streaming）
│   ├── Conversation.swift        # 会话模型
│   ├── ToolCall.swift            # 工具调用与结果模型
│   ├── ModelCapabilities.swift   # 模型能力矩阵（Claude/GPT/Qwen/DeepSeek 等）
│   ├── MultiAgentConfig.swift    # 多 Agent 配置（Orchestrator/Worker/Router/TaskPlan）
│   └── ConfigSet.swift           # 配置集管理（Keychain API Key 存储）
├── Views/                  # SwiftUI 界面
│   ├── ContentView.swift         # 主界面（侧边栏 + 主内容区）
│   ├── NewChatPage.swift         # 新建对话页
│   ├── SettingsView.swift        # 设置页
│   ├── MultiAgentSettingsView.swift # 多 Agent 设置
│   ├── ConfigSetManagementView.swift # ConfigSet 管理
│   ├── EnhancedMessageBubble.swift   # 消息气泡
│   ├── EnhancedToolCallCard.swift    # 工具调用卡片
│   ├── ToolExecutionView.swift       # 工具执行视图
│   ├── FileOperationAnimationView.swift # 文件操作动画
│   ├── MarkdownRenderer.swift    # Markdown 渲染器
│   ├── TaskPlanView.swift        # 任务计划视图
│   ├── ContextPanel.swift        # 上下文面板
│   └── MessageBubble.swift       # 基础消息气泡
├── ViewModels/             # 视图模型
│   └── ComposerInputState.swift  # 输入状态与文件引用管理
├── Utils/                  # 工具类
│   ├── ProcessRunner.swift       # 进程运行器
│   ├── PermissionManager.swift   # 权限管理
│   ├── KeychainManager.swift     # Keychain 安全存储
│   ├── PathSecurity.swift        # 路径安全检查（防止目录遍历）
│   └── Logger.swift              # 统一日志（os.Logger）
├── Theme/                  # 主题设计系统
│   └── Theme.swift               # 颜色、渐变、间距、圆角、阴影定义
└── Tests/                  # 单元测试
    ├── SafetyRegressionTests.swift   # 安全回归测试（命令分类）
    ├── ModelCapabilitiesTests.swift  # 模型能力测试
    ├── MultiAgentRoutingTests.swift  # 多 Agent 路由测试
    └── KeychainManagerTests.swift    # Keychain 测试
```

## 开发指南

### 添加新工具

1. 在 `Tools/` 创建实现 `Tool` 协议的类（需提供 `name`、`description`、`parameters`、`execute`）
2. 在 `ToolRegistry.registerDefaultTools()` 中注册

### 添加新 AI 服务

1. 在 `Services/` 创建实现 `AIService` 协议的类
2. 在 `AIServiceFactory.createService()` 中添加新提供商分支

### 更新 Xcode 项目

```bash
# 新增 Swift 文件后重新生成项目
xcodegen generate
```

Xcode 项目由 xcodegen 从 `project.yml` 生成，不要手动修改 `.xcodeproj`。

## 构建方式

| 方式 | 用途 | 说明 |
|------|------|------|
| `open RioAgent.xcodeproj` | Xcode 开发调试 | 支持断点、Debug Console、UI 预览 |
| `swift build` / `swift run` | 命令行快速构建 | 生成命令行可执行文件 |
| `./create_app.sh` | 打包 .app | 优先走稳定签名；若本机未配置开发签名，则自动回退到未签名本地模式 |
| `RIO_DEVELOPMENT_TEAM=... ./create_app.sh` | 打包已签名 .app | 生成稳定签名的 macOS 应用包，首次授权后可持续复用 Keychain 身份 |
| `./create_app.sh --unsigned` | 打包未签名 .app | 不使用 Keychain，API Key 改存本地 UserDefaults，避免重复密码弹窗 |
| `./build.sh build` | 构建脚本 | 封装常用构建命令 |

## 注意事项

- Xcode 项目由 xcodegen 从 `project.yml` 生成，不要手动修改 `.xcodeproj`
- Info.plist 使用 linker flags 嵌入二进制文件（SPM 方式，见 `Package.swift` 的 `linkerSettings`）
- API Key 存储在 macOS Keychain 中，配置元数据存储在 UserDefaults
- 若本机没有 Apple Development 证书，`./create_app.sh` 会自动回退到未签名本地模式，并禁用 Keychain 以避免重复密码弹窗
- 若想继续使用 Keychain，请配置开发签名并在首次 Keychain 提示时选择“总是允许”
- 流式响应使用 SSE（Server-Sent Events）格式解析
- 模型能力矩阵（`ModelCapabilities`）覆盖 Claude / GPT / Qwen / DeepSeek / Gemini 等主流模型，自动检测上下文窗口大小和特性支持

## 许可证

MIT License
