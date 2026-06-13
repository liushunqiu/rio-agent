# Rio Agent

一个类似 OpenAI Codex CLI 的 macOS 原生 AI Agent 应用，使用 Swift 5.9+ 和 SwiftUI 构建。

## 功能特性

- **多 AI 支持**：支持 Claude 和 OpenAI API
- **对话式交互**：原生 SwiftUI 界面，流畅的对话体验
- **工具调用**：Shell 命令执行、文件读写等能力
- **安全确认**：严格的风险分类和确认机制
- **历史保存**：对话历史自动保存
- **原生体验**：macOS 原生应用，支持暗黑模式

## 系统要求

- macOS 14.0+
- Xcode 15.0+
- Swift 5.9+

## 快速开始

### 1. 克隆项目

```bash
git clone <repository-url>
cd rio-agent
```

### 2. 使用 Xcode 开发（推荐）

```bash
# 直接打开 Xcode 项目
open RioAgent.xcodeproj
```

在 Xcode 中按 `⌘R` 即可构建运行，支持断点调试和 Debug Console。

### 3. 命令行构建

```bash
# 使用 Swift Package Manager
swift build

# 使用构建脚本
./build.sh build
```

### 4. 命令行运行

```bash
# 使用 Swift Package Manager
swift run

# 使用运行脚本
./run.sh
```

### 5. 打包为 macOS 应用

```bash
./create_app.sh
```

生成的 `Rio Agent.app` 可以直接双击运行或拖入 Applications 文件夹。

## 配置 API Key

1. 启动应用后，点击右上角的齿轮图标打开设置
2. 选择 AI 提供商（Claude 或 OpenAI）
3. 输入对应的 API Key
4. 点击"完成"保存设置

## 使用方法

### 基本对话

1. 在输入框中输入你的问题或指令
2. 按回车或点击发送按钮
3. AI 会回复你的问题

### 执行命令

当你请求 AI 执行 shell 命令时：

1. AI 会显示即将执行的命令
2. 弹出确认对话框
3. 点击"执行"确认，或"取消"放弃

### 文件操作

- **读取文件**：AI 可以读取指定路径的文件内容
- **写入文件**：写入文件前会显示预览并请求确认

## 项目架构

```
rio-agent/
├── RioAgent.xcodeproj   # Xcode 项目文件（xcodegen 生成）
├── project.yml           # xcodegen 配置（修改后运行 xcodegen generate 重新生成）
├── Package.swift         # Swift Package Manager 配置
├── Agent/                # Agent 引擎核心
│   ├── AgentEngine.swift       # 单 Agent 对话引擎
│   └── MultiAgentEngine.swift  # 多 Agent 协作引擎
├── Services/             # AI API 服务层
│   ├── AIService.swift         # 服务协议定义和工厂类
│   ├── ClaudeService.swift     # Claude API 实现
│   └── OpenAIService.swift     # OpenAI/兼容 API 实现
├── Tools/                # 工具系统
│   ├── ToolProtocol.swift      # 工具协议、CommandClassifier
│   ├── ToolRegistry.swift      # 工具注册中心
│   ├── ShellTool.swift         # Shell 命令执行
│   └── ...其他工具实现
├── Models/               # 数据模型
├── Views/                # SwiftUI 界面组件
├── ViewModels/           # 视图模型
├── Utils/                # 工具类
└── Theme/                # 主题配置
```

## 支持的工具

| 工具名称 | 描述 |
|---------|------|
| `execute_command` | 执行 shell 命令 |
| `read_file` | 读取文件内容 |
| `write_file` | 写入文件内容 |
| `search_files` | 搜索文件内容 |
| `find_files` | 查找文件 |
| `list_directory` | 列出目录内容 |

## 安全特性

### 命令风险分类

工具通过 `CommandClassifier.classify()` 进行风险分类：

- **safe**：只读命令（ls, cat, grep, git status 等）-> 自动执行
- **normal**：大多数命令 -> 需要用户确认
- **dangerous**：危险命令（rm, sudo, curl, wget 等）-> 始终需要确认

### 安全机制

- **严格确认模式**：所有非安全命令都需要用户明确确认
- **权限管理**：文件访问需要用户授权
- **API Key 安全**：API Key 存储在 UserDefaults 中
- **流式响应**：使用 SSE（Server-Sent Events）格式解析 AI 响应

## 开发指南

### 添加新工具

1. 在 `Tools/` 目录下创建新的工具类
2. 实现 `Tool` 协议
3. 在 `ToolRegistry` 中注册新工具

### 添加新 AI 服务

1. 在 `Services/` 目录下创建新的服务类
2. 实现 `AIService` 协议
3. 在 `AIServiceFactory` 中添加新的提供商

### 新增源文件后更新 Xcode 项目

如果通过命令行新增了 Swift 文件，需要重新生成 Xcode 项目：

```bash
xcodegen generate
```

或者直接在 Xcode 中右键项目 -> Add Files to "RioAgent" 添加文件。

### 运行测试

```bash
swift test
```

## 构建方式说明

| 方式 | 用途 | 说明 |
|------|------|------|
| `open RioAgent.xcodeproj` | Xcode 开发调试 | 支持断点、Debug Console、UI 预览 |
| `swift build` / `swift run` | 命令行快速构建 | 生成命令行可执行文件，不出现在 Dock |
| `./create_app.sh` | 打包 .app | 生成独立的 macOS 应用包 |

## 注意事项

- Xcode 项目由 xcodegen 从 `project.yml` 生成，不要手动修改 `.xcodeproj`，改 `project.yml` 后重新 `xcodegen generate`
- Info.plist 使用 linker flags 嵌入二进制文件（SPM 方式）
- 开发阶段允许任意网络请求（NSAllowsArbitraryLoads）
- 所有非安全命令都需要通过 `ConfirmationCallback` 确认

## 许可证

MIT License

## 贡献

欢迎提交 Issue 和 Pull Request！
