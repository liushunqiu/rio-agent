# Router Skip 导致工具调用失效的修复

## 问题描述

从用户截图看到，AI 模型输出了**文本形式的工具调用**（XML 格式），而不是通过 API 的 function calling 机制：

```
我来查看当前项目目录结构。<tool_call>
<function=list_directory>
<parameter=path>/Users/liushunqiu/Desktop/ota</parameter>
</function>
</tool_call>
```

这表明工具调用完全失效了。

## 根本原因分析

经过深入调查，发现了一个严重的 Bug：

### 1. Router 决策链路

```
用户消息 → RouterService → 决策结果 (.skip 或 .routeToTarget)
                                  ↓
                     AgentEngine.currentRouterDecision
                                  ↓
                     processConversationLoop(Streaming)
                                  ↓
                     enableTools = (currentRouterDecision != .skip)
                                  ↓
                     tools: enableTools ? [...] : []  ← 如果是 skip，传空数组！
```

### 2. 当 Router 判断为 `.skip` 时

- `enableTools = false`
- AI 请求中 `tools: []`（空数组）
- **AI 完全不知道有可用的工具**
- AI 只能用文本形式描述工具调用

### 3. TextToolCallSafetyNet 的无效循环

虽然 `TextToolCallSafetyNet` 能检测到文本形式的工具调用并注入纠正提示：

```swift
// TextToolCallSafetyNet 检测到问题
if containsTextBasedToolCalls(content) {
    // 注入纠正提示
    messages.append(correctionMessage)
    return true  // 继续循环
}
```

**但问题是：**
- `enableTools` 在循环开始前就被固定为 `let` 常量
- 下一轮迭代时，`tools` 参数**仍然是空数组**
- AI 依然不知道有工具可用
- 死循环直到达到最大重定向次数（2次）

### 4. Bug 的触发条件

只要满足以下条件就会触发：

1. Router 启用（`multiAgentConfig.router.enabled = true`）
2. Router 判断用户消息为 `.skip`（认为不需要工具）
3. 但用户的实际需求**确实需要工具**（如 "查看项目目录结构"）
4. 安全兜底 `applySkipSafetyOverride` 未能覆盖（关键词匹配不足）

## 修复方案

### 核心思路

**当 AI 尝试调用工具时，这本身就证明 Router 的 skip 决策是错误的！**

因此，应该在 `TextToolCallSafetyNet` 检测到工具调用意图时，**动态覆盖 Router 决策**。

### 实现细节

#### 1. 修改 `TextToolCallSafetyNet.swift`

在 `handleTextToolCallRedirect` 中添加 Router 决策覆盖逻辑：

```swift
func handleTextToolCallRedirect(_ content: String) -> Bool {
    guard textToolCallRedirectCount < Self.maxTextToolCallRedirects else {
        return false
    }

    guard Self.containsTextBasedToolCalls(content) else {
        return false
    }

    textToolCallRedirectCount += 1

    // ✅ 新增：覆盖 Router 的 skip 决策
    overrideRouterSkipIfNeeded()
    
    // ... 注入纠正提示 ...
}
```

添加新方法：

```swift
extension AgentEngine {
    /// Override Router's skip decision when the model attempts to use tools.
    func overrideRouterSkipIfNeeded() {
        if case .skip = currentRouterDecision {
            RioLogger.agent.warning("⚠️ 检测到工具调用意图，覆盖 Router 的 skip 决策，启用工具")
            currentRouterDecision = .routeToTarget(
                target: "process",
                params: [:],
                confidence: 0.7,
                reasoning: "模型尝试调用工具，覆盖原 skip 决策"
            )
        }
    }
}
```

#### 2. 修改 `AgentEngine.swift`

##### 2.1 将 `currentRouterDecision` 改为 `internal`

```swift
// 从 private 改为 internal，允许 TextToolCallSafetyNet 访问
internal var currentRouterDecision: RoutingDecision?
```

##### 2.2 动态读取 `enableTools`（流式路径）

```swift
private func processConversationLoopStreaming(aiService: AIService) async throws {
    let model = configuration.executionModel
    var thinkingStartTime: Date?
    var hasThinkingContent = false

    try await ConversationLoop.run(engine: self) { contextMessages in
        // ✅ 移到循环内部，每次迭代都重新读取
        let enableTools: Bool
        if case .skip = self.currentRouterDecision {
            enableTools = false
            RioLogger.service.info("🔀 Router 决策为 skip，禁用工具调用")
        } else {
            enableTools = true
            RioLogger.service.info("🔀 Router 决策为 process，启用工具调用")
        }
        
        // ... 使用 enableTools ...
    }
}
```

##### 2.3 同步修改非流式路径

```swift
private func processConversationLoop(aiService: AIService) async throws {
    let model = configuration.executionModel

    try await ConversationLoop.run(engine: self) { contextMessages in
        // ✅ 同样移到循环内部
        let enableTools: Bool
        if case .skip = self.currentRouterDecision {
            enableTools = false
        } else {
            enableTools = true
        }
        
        return try await aiService.sendMessage(
            contextMessages,
            tools: enableTools ? self.toolRegistry.getToolDefinitions() : [],
            model: model,
            maxTokens: self.configuration.maxTokens
        )
    }
}
```

## 修复效果

### Before（有 Bug）

```
用户: "查看当前项目目录结构"
  ↓
Router: skip (认为是简单问题)
  ↓
enableTools = false (固定)
  ↓
第1轮: AI 收到 tools: []
       AI 输出: "我来查看当前项目目录结构。<tool_call>..."
  ↓
TextToolCallSafetyNet: 检测到问题，注入纠正提示
  ↓
第2轮: AI 收到 tools: [] (仍然是空！)
       AI 输出: 同样的文本形式工具调用
  ↓
达到最大重定向次数，放弃修正
  ↓
用户看到: 原始的 XML 文本输出
```

### After（修复后）

```
用户: "查看当前项目目录结构"
  ↓
Router: skip (认为是简单问题)
  ↓
第1轮: enableTools = false (动态读取 currentRouterDecision)
       AI 收到 tools: []
       AI 输出: "我来查看当前项目目录结构。<tool_call>..."
  ↓
TextToolCallSafetyNet: 检测到问题
                       ✅ 调用 overrideRouterSkipIfNeeded()
                       ✅ currentRouterDecision 被改为 .routeToTarget
                       注入纠正提示
  ↓
第2轮: enableTools = true (动态读取，发现已经不是 skip)
       AI 收到 tools: [完整的工具定义数组]
       AI 正确调用: list_directory(path="/Users/...")
  ↓
工具执行成功，返回目录内容
  ↓
用户看到: 正确的工具执行结果
```

## 测试覆盖

新增测试文件 `RouterSkipToolEnablementTests.swift`：

### 测试用例

1. **testTextToolCallSafetyNetOverridesRouterSkipDecision**
   - 验证当 Router 决策为 skip 时，`overrideRouterSkipIfNeeded()` 能正确覆盖为 process

2. **testOverrideOnlyAffectsSkipDecisions**
   - 验证对于非 skip 的决策，override 不会产生影响

3. **testOverrideHandlesNilRouterDecision**
   - 验证当没有 Router 决策时，override 是安全的 no-op

### 测试结果

```
✔ Test Suite 'RouterSkipToolEnablementTests' passed
  Executed 3 tests, with 0 failures in 0.008 seconds
```

## 相关文件

### 修改的文件

- `Agent/TextToolCallSafetyNet.swift`
  - 添加 `overrideRouterSkipIfNeeded()` 方法
  - 在 `handleTextToolCallRedirect` 中调用覆盖逻辑

- `Agent/AgentEngine.swift`
  - 将 `currentRouterDecision` 访问级别从 `private` 改为 `internal`
  - 将 `enableTools` 计算移到 `ConversationLoop.run()` 的闭包内部（流式和非流式路径）

### 新增的文件

- `Tests/RouterSkipToolEnablementTests.swift`
  - 3个测试用例验证修复逻辑

## 兼容性

### 不会影响的场景

1. **Router 未启用**：`currentRouterDecision` 保持 `nil`，工具始终启用
2. **Router 决策为 process**：工具始终启用，无需覆盖
3. **AI 正确使用工具**：不触发 `TextToolCallSafetyNet`，无覆盖行为

### 改进的场景

1. **Router 误判 skip**：当 AI 尝试使用工具时自动纠正
2. **模型兼容性**：某些模型在没有工具定义时会输出文本形式调用，现在能自适应

## 结论

这个修复解决了 Router 的 skip 决策与实际工具需求不匹配的问题，通过**动态覆盖机制**让系统能够自我纠正，确保 AI 始终能在需要时访问工具定义。

**核心原则**：AI 的行为是需求的最终仲裁者——如果 AI 试图调用工具，那它确实需要工具，Router 的静态判断应该让位于动态运行时证据。
