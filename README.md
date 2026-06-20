# Rio Agent

<div align="center">

**原生 macOS AI 编程助手 · Swift 5.9+ · SwiftUI**

支持多 AI 提供商 · 多 Agent DAG 协作 · 智能任务规划 · Critic 错误自愈

[快速开始](#快速开始) · [核心特性](#核心特性) · [架构设计](#架构设计) · [开发指南](#开发指南)

</div>

---

## 系统要求

- macOS 14.0+
- Xcode 15.0+
- Swift 5.9+

## 快速开始

### 方式 1：Xcode 开发（推荐）

```bash
open RioAgent.xcodeproj
```

支持断点调试、UI 预览、完整 IDE 功能。

### 方式 2：命令行构建

```bash
# 构建
swift build

# 运行
swift run

# 运行测试
swift test
```

### 方式 3：打包 .app

```bash
# 自动选择：有签名证书时使用 Keychain，否则回退到本地存储
./create_app.sh

# 强制使用开发签名（需要 Apple Developer Team ID）
RIO_DEVELOPMENT_TEAM=ABCDE12345 ./create_app.sh

# 强制未签名模式（API Key 存储在 UserDefaults）
./create_app.sh --unsigned
```

**签名说明**：
- 使用 Keychain 存储 API Key 需要应用签名
- 首次运行时选择"总是允许"以避免重复弹窗
- 未签名模式自动切换到 UserDefaults 存储

### 构建脚本快捷方式

```bash
./build.sh build    # 构建
./build.sh run      # 构建并运行
./build.sh app      # 打包已签名 .app
./build.sh test     # 运行测试
./build.sh clean    # 清理构建产物
```

---

## 核心特性

### 🤖 双引擎架构

- **单 Agent 引擎（AgentEngine）**  
  处理简单到中等复杂度任务，支持流式输出、工具调用循环（最多 9999 次迭代）、错误自愈

- **多 Agent 引擎（MultiAgentEngine）**  
  四层流水线处理复杂任务：Planner 生成 DAG → 波次并行执行 → Critic 验证 → 结果汇总

### 🛠️ 8 种内置工具

| 工具 | 描述 | 风险等级 |
|------|------|----------|
| `execute_command` | 执行 Shell 命令（支持管道、重定向） | 自动分类 |
| `read_file` | 读取文件内容 | 安全 |
| `write_file` | 写入文件（全量覆盖） | 需确认¹ |
| `edit_file` | 搜索替换编辑 | 需确认¹ |
| `apply_patch` | 应用 unified diff 补丁 | 需确认 |
| `search_files` | 正则搜索文件内容 | 安全 |
| `find_files` | 按名称模式查找文件 | 安全 |
| `list_directory` | 列出目录内容 | 安全 |

<sub>¹ 工作目录外的文件操作需要用户确认</sub>

### 🧠 智能子系统

- **TaskPlanner** — 任务复杂度分析、步骤分解、执行指导
- **AgentMemory** — 短期会话记忆 + 长期偏好学习（工具使用模式、错误历史、编码风格）
- **ProjectAnalyzer** — 自动识别项目类型（iOS/macOS/Web/CLI）、框架、依赖、构建系统
- **CodeNavigator** — 代码符号提取、定义跳转、引用查找（Swift/JS/Python/Rust/Go）
- **MultiFileCoordinator** — 文件关系分析、协调多文件修改
- **RefactoringAdvisor** — 代码异味检测、重构建议
- **CriticService** — 错误分析与修复建议生成

### 🔀 本地路由器（RouterService）

可选的前置拦截层，支持两种模式：

- **通用路由** — 使用配置的 AI 模型判断是否需要处理
- **Qwen3.5-4B 路由** — 本地小模型结构化输出，支持路由到 code_expert / search_agent / data_analyst / chitchat 等目标节点

### 🎯 多提供商支持

- **Claude（Anthropic）** — Sonnet/Opus/Haiku 3.x/4.x，支持 thinking、vision、200K 上下文
- **OpenAI** — GPT-4.x、o1/o3，支持 vision、JSON 模式，最高 1M 上下文
- **OpenAI 兼容 API** — DeepSeek、Qwen、Gemini、本地模型等

通过 **ConfigSet** 管理多个模型配置：
- 每个 ConfigSet = 一个模型实例（提供商 + Base URL + 模型名 + API Key）
- API Key 安全存储在 macOS Keychain 中
- 可为规划模型和执行模型分别指定不同的 ConfigSet

### 🛡️ 安全机制

#### 命令风险分类（CommandClassifier）

自动分析 Shell 命令风险，支持管道、控制运算符（`&&`、`||`、`;`）、重定向的递归解析：

- **safe** — 只读命令（ls、cat、grep、git status/log/diff）→ 自动执行
- **normal** — 大多数命令 → 需要用户确认
- **dangerous** — 危险命令（rm -rf、sudo、curl、wget、kill -9、sed -i）→ 始终需要确认

#### 路径安全（PathSecurity）

- 防止目录遍历攻击（`../`、符号链接等）
- 工作目录外的文件操作需要用户确认

---

## 架构设计

### 单 Agent 引擎流程

```
用户输入
  ↓
[可选] RouterService 前置拦截
  ↓
TaskPlanner 任务分析
  ↓
ConversationLoop 工具调用循环（最多 9999 次）
  ├─ AI 模型推理
  ├─ 工具调用与结果处理
  ├─ 错误追踪 + Critic 分析（连续错误 ≥2 次）
  └─ 上下文管理（智能 Token 估算、自动压缩）
  ↓
返回结果
```

### 多 Agent 引擎流程

```
用户输入
  ↓
Layer 2: Planner
  Orchestrator 生成 DAG 子任务图（Worker 类型 + 依赖关系）
  ↓
Layer 3: Execution Guild
  按波次并行执行（无依赖任务并行，有依赖任务等待）
  每个 Worker 注入项目上下文（工作目录、git 状态、文件树、AGENT.md）
  ↓
Layer 4: Critic & Verification
  PEV（Plan-Execute-Verify）重试循环
  Critic 分析失败原因并生成修复建议
  ↓
Synthesis: Result Synthesis
  Orchestrator 汇总所有子任务结果
  ↓
返回最终答案
```

**Worker 类型**：
- `search` — 信息检索
- `code` — 代码分析与生成
- `file` — 文件操作
- `general` — 通用任务
- `custom` — 自定义系统提示词

### 上下文管理

- **智能 Token 估算** — 区分 ASCII / CJK / 结构化文本，准确估算上下文消耗
- **自动压缩** — 接近模型上下文限制时，自动压缩旧工具输出
- **项目上下文注入** — 多 Agent 模式下，每个 Worker 自动获取项目状态（工作目录、git 状态、文件树、AGENT.md）

---

## UI 特性

- ✨ **暗黑模式原生设计** — 自定义 Theme 设计系统
- 🚀 **流式 Markdown 渲染** — 智能缓冲合并（12fps + 500 字符批量刷新）
- 🔧 **工具调用可视化** — 状态卡片 + 文件操作动画
- 📁 **多会话管理** — 侧边栏切换、自动标题生成
- 📋 **任务计划实时展示** — TaskPlanView 可视化任务分解与执行进度
- 💭 **Thinking Content 折叠显示** — 支持 Claude extended thinking
- 📎 **文件引用管理** — 支持拖拽文件到输入框，自动提取内容并注入上下文

---

## 内置命令

| 命令 | 描述 |
|------|------|
| `/init` | AI 分析项目结构并生成 AGENT.md 上下文文件 |
| `/clear` | 清除当前对话历史 |
| `/compact` | 压缩对话上下文，节省 Token 消耗 |
| `/export` | 导出当前对话为 Markdown 文件 |
| `/help` | 显示帮助信息 |

---

## 项目结构

```
rio-agent/
├── App/                    # 应用入口与全局状态
│   ├── RioAgentApp.swift         # @main 入口
│   └── AppState.swift            # 全局配置、错误定义
├── Agent/                  # Agent 引擎核心
│   ├── AgentEngine.swift         # 单 Agent 对话引擎
│   ├── MultiAgentEngine.swift    # 多 Agent 协作引擎
│   ├── ConversationLoop.swift    # 统一执行循环（流式 + 非流式）
│   ├── TaskPlanner.swift         # 任务分析与分解
│   ├── AgentMemory.swift         # 记忆系统
│   ├── CriticService.swift       # Critic 错误分析
│   ├── ProjectAnalyzer.swift     # 项目结构分析
│   ├── CodeNavigator.swift       # 代码导航
│   ├── MultiFileCoordinator.swift# 多文件协调
│   └── RefactoringAdvisor.swift  # 重构建议
├── Services/               # AI API 服务层
│   ├── AIService.swift           # 协议 + 工厂 + SSE 解析器
│   ├── ClaudeService.swift       # Claude API
│   ├── OpenAIService.swift       # OpenAI / 兼容 API
│   └── RouterService.swift       # 路由服务
├── Tools/                  # 工具系统
│   ├── ToolProtocol.swift        # Tool 协议、CommandClassifier
│   ├── ToolRegistry.swift        # 工具注册中心
│   ├── ToolRecommender.swift     # 工具智能推荐
│   └── [8 种内置工具实现]
├── Models/                 # 数据模型
│   ├── Message.swift             # 消息模型
│   ├── Conversation.swift        # 会话模型
│   ├── ToolCall.swift            # 工具调用与结果
│   ├── ModelCapabilities.swift   # 模型能力矩阵
│   ├── MultiAgentConfig.swift    # 多 Agent 配置
│   └── ConfigSet.swift           # ConfigSet 管理
├── Views/                  # SwiftUI 界面
│   ├── ContentView.swift         # 主界面
│   ├── SettingsView.swift        # 设置页
│   ├── MultiAgentSettingsView.swift # 多 Agent 设置
│   ├── ConfigSetManagementView.swift # ConfigSet 管理
│   ├── EnhancedMessageBubble.swift   # 消息气泡
│   ├── EnhancedToolCallCard.swift    # 工具调用卡片
│   ├── MarkdownRenderer.swift    # Markdown 渲染器
│   └── TaskPlanView.swift        # 任务计划视图
├── ViewModels/             # 视图模型
│   └── ComposerInputState.swift  # 输入状态与文件引用管理
├── Utils/                  # 工具类
│   ├── ProcessRunner.swift       # 进程运行器
│   ├── PermissionManager.swift   # 权限管理
│   ├── KeychainManager.swift     # Keychain 安全存储
│   ├── PathSecurity.swift        # 路径安全检查
│   └── Logger.swift              # 统一日志
├── Theme/                  # 主题设计系统
│   └── Theme.swift               # 颜色、渐变、间距、圆角、阴影
└── Tests/                  # 单元测试
    ├── SafetyRegressionTests.swift   # 安全回归测试
    ├── ModelCapabilitiesTests.swift  # 模型能力测试
    ├── MultiAgentRoutingTests.swift  # 多 Agent 路由测试
    └── KeychainManagerTests.swift    # Keychain 测试
```

---

## 开发指南

### Xcode 项目管理

⚠️ **重要**：Xcode 项目由 xcodegen 从 `project.yml` 生成，**不要手动修改 `.xcodeproj`**。

```bash
# 新增/删除 Swift 文件后重新生成项目
xcodegen generate
```

### 添加新工具

1. 在 `Tools/` 创建实现 `Tool` 协议的类
2. 实现 `name`、`description`、`parameters`、`execute(arguments:)`
3. 在 `ToolRegistry.registerDefaultTools()` 中注册

示例：

```swift
class MyTool: Tool {
    let name = "my_tool"
    let description = "工具描述"
    let parameters: [String: Any] = [
        "type": "object",
        "properties": [
            "param": ["type": "string", "description": "参数描述"]
        ],
        "required": ["param"]
    ]
    
    func execute(arguments: [String: Any]) async throws -> String {
        // 工具实现
        return "执行结果"
    }
}
```

### 添加新 AI 服务提供商

1. 在 `Services/` 创建实现 `AIService` 协议的类
2. 在 `AIProvider` 枚举中添加新 case（`AppState.swift`）
3. 在 `AIServiceFactory.createService()` 中添加新提供商分支

### 测试命令分类

**安全关键逻辑** — 修改 `CommandClassifier` 时务必在 `SafetyRegressionTests.swift` 添加测试用例：

```swift
func testCommandRiskLevel() {
    XCTAssertEqual(CommandClassifier.classify("ls -la"), .safe)
    XCTAssertEqual(CommandClassifier.classify("rm -rf /"), .dangerous)
    XCTAssertEqual(CommandClassifier.classify("git commit"), .normal)
    
    // 测试复合命令
    XCTAssertEqual(CommandClassifier.classify("ls && rm -rf /"), .dangerous)
}
```

### 运行测试

```bash
# 命令行
swift test

# Xcode
⌘U
```

关键测试套件：
- `SafetyRegressionTests` — 命令风险分类
- `ModelCapabilitiesTests` — 模型模式匹配
- `MultiAgentRoutingTests` — DAG 依赖解析
- `KeychainManagerTests` — 安全存储操作

---

## 技术细节

### Info.plist 嵌入

项目使用 SPM 的 `linkerSettings` 将 `Info.plist` 嵌入二进制文件（见 `Package.swift`），而非单独打包。plist 链接在 `__TEXT/__info_plist` 段。

### API Key 存储策略

| 签名状态 | 存储方式 | 说明 |
|----------|----------|------|
| 已签名 | macOS Keychain | 安全存储，需首次授权"总是允许" |
| 未签名 | UserDefaults | 避免重复密码弹窗，适合本地开发 |

配置元数据（provider、baseURL、model name）始终存储在 UserDefaults。

### 流式响应解析

使用 SSE（Server-Sent Events）格式，通过 `data:` 前缀标识数据块。支持不完整块的缓冲积累与断点续传。

### 模型能力矩阵

`ModelCapabilities` 使用数据驱动的模式匹配数据库，覆盖 30+ 模型：

- **模式顺序敏感** — 更具体的模式（如 `gpt-4.1`）必须排在通用模式（如 `gpt-4`）之前
- **自动检测** — 上下文窗口大小、thinking 模式、vision 支持、JSON 模式等

---

## 常见问题

### 1. 为什么重复弹出 Keychain 密码框？

**原因**：应用未签名或签名不稳定。

**解决方案**：
```bash
# 方式 1：使用稳定签名（推荐）
RIO_DEVELOPMENT_TEAM=YOUR_TEAM_ID ./create_app.sh

# 方式 2：使用未签名模式（自动切换到 UserDefaults 存储）
./create_app.sh --unsigned
```

### 2. 如何切换 AI 模型？

在设置页面（右上角齿轮图标）：
1. 点击"管理 ConfigSet"
2. 添加新的 ConfigSet（提供商 + Base URL + 模型名 + API Key）
3. 在"执行模型"下拉框中选择新的 ConfigSet

### 3. 多 Agent 模式什么时候触发？

在设置页面启用"多 Agent 协作"，AI 会根据任务复杂度自动选择：
- **simple / moderate** → 单 Agent 引擎
- **complex / veryComplex** → 多 Agent 引擎

### 4. 如何配置本地路由器（Qwen3.5-4B）？

1. 启动本地 OpenAI 兼容 API 服务（如 vLLM、Ollama）
2. 在设置页面启用"使用路由器"
3. 选择"Qwen3.5-4B 路由"
4. 配置 Base URL 和模型名

**关键配置**：必须禁用 thinking 模式以避免 JSON 结构破坏：
```json
{
  "chat_template_kwargs": {
    "enable_thinking": false
  }
}
```

### 5. 项目上下文如何注入？

- **单 Agent 模式** — 在 AGENT.md 文件中维护项目上下文，AI 自动读取
- **多 Agent 模式** — `MultiAgentEngine.buildProjectContext()` 自动生成富上下文（工作目录、git 状态、文件树、AGENT.md），注入每个 Worker

---

## 依赖声明

🚀 **零外部依赖** — 纯 Swift 标准库 + Foundation + SwiftUI

所有功能从零实现：
- SSE 解析
- JSON 处理
- 进程执行
- Keychain 操作

最小化供应链风险。

---

## 贡献指南

欢迎提交 Issue 和 Pull Request！

提交前请确保：
1. ✅ 所有测试通过（`swift test`）
2. ✅ 代码符合项目风格
3. ✅ 关键逻辑变更添加测试用例（尤其是 `CommandClassifier`、`ModelCapabilities`）

---

## 许可证

MIT License

---

## 致谢

感谢以下开源项目的灵感：
- [Claude API](https://docs.anthropic.com/)
- [OpenAI API](https://platform.openai.com/docs/)
- [SwiftUI](https://developer.apple.com/xcode/swiftui/)

---

<div align="center">

**Made with ❤️ using Swift & SwiftUI**

</div>
