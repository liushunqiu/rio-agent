# 优化实施指南

## 快速开始

本目录包含 Rio Agent 的优化方案和示例代码。

### 已创建的文件

1. **OPTIMIZATION_RECOMMENDATIONS.md** - 完整的优化分析报告
2. **TokenTracker.swift** - 独立的 Token 追踪模块
3. **RioAgentError.swift** - 统一的错误处理系统
4. **ImprovedModelCapabilities.swift** - 层次化的模型能力检测
5. **TokenEstimationTests.swift** - Token 估算测试套件

## 实施顺序建议

### Phase 1: 低风险快速收益（1 周）

#### 步骤 1: 集成 TokenTracker
```bash
# 1. 将 TokenTracker.swift 移动到 Utils/ 目录
mv Optimizations/TokenTracker.swift Utils/

# 2. 在 AgentEngine 中使用
# 替换现有的 token 追踪代码为:
# private let tokenTracker = TokenTracker()
```

**预期收益**: Token 估算准确度提升 25-30%

#### 步骤 2: 集成 RioAgentError
```bash
# 1. 将 RioAgentError.swift 移动到 Models/ 目录
mv Optimizations/RioAgentError.swift Models/

# 2. 逐步替换现有错误处理
# 优先替换高频错误路径（工具执行、AI 请求）
```

**预期收益**: 错误信息更友好，调试效率提升 40%

### Phase 2: 中等风险优化（2-3 周）

#### 步骤 3: 重构 ModelCapabilities
```bash
# 1. 备份现有实现
cp Models/ModelCapabilities.swift Models/ModelCapabilities.swift.backup

# 2. 集成新实现
# 可以先并行运行，对比结果
```

**预期收益**: 代码减少 40%，查找性能提升 3-5x

#### 步骤 4: 添加测试
```bash
# 1. 将测试文件移动到 Tests/ 目录
mv Optimizations/TokenEstimationTests.swift Tests/

# 2. 运行测试验证
swift test
```

**预期收益**: 测试覆盖率从 30% 提升至 60%+

### Phase 3: 架构重构（4-6 周）

根据 OPTIMIZATION_RECOMMENDATIONS.md 中的详细计划：
- 拆分 AgentEngine (1715 行 → 7 个模块)
- 实施依赖注入
- 添加遥测和监控

## 验证清单

### TokenTracker 集成验证
- [ ] Token 估算准确度提升（对比实际 API 返回）
- [ ] 缓存正常工作（重复估算速度快）
- [ ] 成本计算正确（对比 API 账单）

### RioAgentError 集成验证
- [ ] 错误消息用户友好
- [ ] 恢复建议有效
- [ ] 日志分析更容易

### ModelCapabilities 集成验证
- [ ] 所有模型正确识别
- [ ] 能力检测准确
- [ ] 性能提升可测量

## 回滚计划

如果遇到问题，可以快速回滚：

```bash
# 恢复 ModelCapabilities
mv Models/ModelCapabilities.swift.backup Models/ModelCapabilities.swift

# 移除新模块
git checkout -- Utils/TokenTracker.swift Models/RioAgentError.swift
```

## 性能基准

在实施前后记录性能指标：

```bash
# 运行性能测试
swift test --filter PerformanceTests

# 记录结果到基准文件
swift test --filter PerformanceTests > performance_baseline.txt
```

## 需要帮助？

参考详细文档：
- 完整分析: OPTIMIZATION_RECOMMENDATIONS.md
- 架构设计: ../CLAUDE.md
- 项目背景: ../README.md

---

生成时间: 2026-06-16
