## 从 OpenRouter Fusion 看 Rio Agent 的优化方向

### 文章核心观点

量子位这篇文章介绍了 OpenRouter 的 Fusion 多模型融合方案。核心发现是：让多个模型并行处理同一任务，再由判定模型综合分析各家输出（共识、矛盾、信息缺口、独到见解），最终生成的答案质量显著优于单一模型。

几个关键数据点：

- Opus 4.8 + GPT-5.5 组合得分 69.0%，超过两个模型单独参赛
- Kimi K2.6 + DeepSeek V4 Pro + Gemini 3 Flash 组合得分 64.7%，几乎追平 Claude Fable 5（65.3%），但成本只有 Fable 5 的 20%~50%
- 即使是同一模型自我融合（如 Opus 4.8 × 3），得分也从 58.8% 提升到 65.5%——说明融合流程本身（答案整合、逻辑梳理）就能优化输出质量

---

### Rio Agent 现状分析

Rio Agent 的角色分离设计（规划模型、执行模型、Critic 模型、路由模型、编排模型、Worker 模型）已经很成熟，ConfigSet 系统允许每个角色使用不同模型和不同 Provider。

在此基础上，我们从文章中借鉴了三个可落地的优化方向（不含多模型并行融合和自融合）。

---

### 已实现的优化

#### 1. Critic 多模型串行评审

**文章依据**：多模型协同整体效果强于单一模型。

**实现方式**（`Agent/CriticService.swift`）：

- 新增 `secondaryService` / `secondaryModel` 可选属性（备用 Critic 模型）
- 新增 `init(aiService:model:secondaryService:secondaryModel:maxTokens:)` 构造器
- 原有单模型 init 保持不变（向后兼容）
- `analyze()` 逻辑升级：
  - 先调用主 Critic 模型
  - 如果主 Critic 失败或输出过短（<50 字符），调用备用 Critic
  - 如果两者都成功，调用 `mergeCriticAnalyses()` 让主模型综合两份分析
- 新增 `mergeCriticAnalyses()` 方法：向主模型发送合并提示，综合两份专家意见

**推荐配置**：主 Critic 用规划模型（如 Claude Sonnet 4），备用 Critic 用 DeepSeek V3 或 Gemini Flash（低成本）

#### 2. Token 成本追踪与定价体系

**文章依据**：在多模型场景下，成本监控对用户选择模型组合至关重要。

**实现方式**：

`Models/ModelCapabilities.swift`：
- 新增 `ModelPricing` 结构体，含 `inputPerMillion` / `outputPerMillion` 属性和 `cost()` 计算方法
- 新增 `ModelCapabilities.pricing(for:)` 静态方法，内置 30+ 模型的公开定价

`Agent/AgentEngine.swift`：
- 新增 `@Published var sessionCost: Double` 属性
- `trackUsage()` 升级为同时累加 token 数和计算费用
- 新增 `getSessionUsageSummary()` 返回格式化的用量和费用摘要（USD + CNY）
- 流式和非流式两条路径都已接入费用追踪

#### 3. Worker 模型性价比预设

**文章依据**：Kimi K2.6 + DeepSeek V4 Pro + Gemini 3 Flash 的平价组合几乎追平 Fable 5。

**实现方式**（`Models/MultiAgentConfig.swift`）：

- `budgetWorkers`：搜索用 Gemini 2.0 Flash + 代码用 DeepSeek Chat + 文件用 Gemini 1.5 Flash
- `premiumWorkers`：搜索用 Gemini 2.5 Pro + 代码用 Claude Sonnet 4 + 文件用 GPT-4o
- `availablePresets`：提供三档预设列表（默认/性价比/高性能），供 UI 直接调用

---

### 各优化涉及的文件变更

| 文件 | 变更内容 |
|---|---|
| `Agent/CriticService.swift` | 新增备用 Critic 支持、`mergeCriticAnalyses()`、多模型 init |
| `Agent/AgentEngine.swift` | 新增 `sessionCost`、`resetUsageTracking()`、`getSessionUsageSummary()`，流式路径加 `trackUsage` |
| `Models/ModelCapabilities.swift` | 新增 `ModelPricing` 结构体和 `pricing(for:)` 静态方法 |
| `Models/MultiAgentConfig.swift` | 新增 `budgetWorkers`、`premiumWorkers`、`availablePresets` |

所有改动均向后兼容，现有调用方无需修改。
