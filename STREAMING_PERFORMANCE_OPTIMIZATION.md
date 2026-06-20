# 流式输出性能优化

## 问题诊断

### 原始问题
用户反馈："我发现在输出流的页面,我们没办法做到像 claude code 这样的输出丝滑！这是非常严重的体验！超级差！"

### 根本原因分析

**问题 1：刷新频率过低（12.5fps）**
- 原代码使用 `interval: 0.08`（80ms），相当于 12.5fps
- Claude Code 等丝滑体验通常是 60fps（16ms）
- 低帧率导致明显的文字"跳动"感

**问题 2：被动检查机制**
```swift
// 旧实现：每次 onChunk 回调都要检查 shouldFlushNow
func flushIfNeeded(update: ...) async {
    guard shouldFlushNow,  // 被动检查
          !contentAccumulator.isEmpty || !thinkingAccumulator.isEmpty else { return }
    // 刷新逻辑
}
```
- 每个 SSE chunk 到达都会调用一次检查
- 高频 API 返回时会产生大量无效检查
- 即使不刷新也要执行检查逻辑

**问题 3：字符批量过大（500 字符）**
- `maxCharsBeforeFlush: 500` 意味着要累积 500 字符才强制刷新
- 对于中文来说可能是 150-200 个汉字
- 用户看到的是大块大块的文字突然出现，不够流畅

## 优化方案

### 核心改进

#### 1. 主动定时器机制
```swift
private func ensureTimerRunning() {
    guard timerTask == nil || timerTask?.isCancelled == true else { return }
    guard let handler = updateHandler else { return }

    timerTask = Task { [weak self] in
        while !Task.isCancelled {
            guard let self, !self.isStopped else { break }
            
            // 主动每 16ms 检查一次，不依赖 onChunk 回调
            try? await Task.sleep(nanoseconds: UInt64(self.interval * 1_000_000_000))
            guard !Task.isCancelled else { break }
            
            if self.shouldFlushNow {
                await self.flushNow(update: handler)
            }
        }
    }
}
```

**优势**：
- ✅ 主动定时检查，不依赖 API 回调频率
- ✅ 稳定的 60fps 刷新，体验丝滑
- ✅ 减少无效检查，性能更好

#### 2. 提升刷新频率到 60fps
```swift
init(interval: TimeInterval = 0.016, maxCharsBeforeFlush: Int = 100) {
    // 从 0.08秒（12.5fps）提升到 0.016秒（60fps）
    self.interval = interval
    // 从 500 字符降低到 100 字符，更细腻
    self.maxCharsBeforeFlush = maxCharsBeforeFlush
}
```

**改进对比**：
| 参数 | 旧值 | 新值 | 提升 |
|------|------|------|------|
| 刷新间隔 | 80ms | 16ms | **5倍** |
| 刷新频率 | 12.5fps | 60fps | **4.8倍** |
| 批量大小 | 500字符 | 100字符 | **更细腻** |

#### 3. 智能批量控制
```swift
private var shouldFlushNow: Bool {
    // 策略 1：达到字符阈值立即刷新（避免单次积累过多）
    if contentAccumulator.count >= maxCharsBeforeFlush { return true }
    if thinkingAccumulator.count >= maxCharsBeforeFlush { return true }

    // 策略 2：达到时间间隔刷新（保证帧率稳定）
    let elapsed = Date().timeIntervalSince(lastFlush)
    return elapsed >= interval
}
```

**双重保障**：
- 字符数阈值：防止单次刷新过多字符（100字符）
- 时间阈值：保证帧率稳定（60fps）

### 渲染层优化

**MessageContent.swift 已有的优化**：
```swift
if message.isStreaming {
    // 流式输出期间使用简单的 Text 视图，避免 Markdown 解析
    Text(message.content)
        .font(.system(size: 14))
        .foregroundColor(Theme.textPrimary)
} else {
    // 流式完成后才解析 Markdown
    MarkdownRenderer(text: message.content)
}
```

这个设计非常聪明：
- ✅ 流式期间不做 Markdown 解析（避免重复解析开销）
- ✅ 只在完成后才渲染完整的 Markdown（语法高亮、代码块等）

## 性能对比

### 优化前
- 刷新频率：**12.5fps**（80ms 间隔）
- 批量大小：**500 字符**
- 检查机制：**被动检查**（每个 chunk 都检查）
- 用户体验：文字"跳动"，不够流畅

### 优化后
- 刷新频率：**60fps**（16ms 间隔）✨
- 批量大小：**100 字符**✨
- 检查机制：**主动定时器**（独立于 API 回调）✨
- 用户体验：**丝滑流畅**，接近 Claude Code 体验 🚀

### 理论性能提升

| 指标 | 优化前 | 优化后 | 提升 |
|------|--------|--------|------|
| UI 刷新延迟 | 80ms | 16ms | **-80%** |
| 帧率 | 12.5fps | 60fps | **+380%** |
| 单批字符数 | 500 字符 | 100 字符 | **更细腻** |
| CPU 检查次数 | 每 chunk 1 次 | 每 16ms 1 次 | **按需优化** |

## 实现细节

### 关键代码位置

**文件**：`Agent/AgentEngine.swift`

**核心类**：`StreamBuffer`（第 2728-2823 行）

**调用位置**：`processConversationLoopStreaming` 方法（第 1331 行）

### 使用方式

```swift
// 创建缓冲器（自动使用 60fps + 100字符批量）
let buffer = StreamBuffer(interval: 0.016, maxCharsBeforeFlush: 100)

// 追加内容（会自动启动定时器）
buffer.appendContent(chunk)
buffer.appendThinking(thinkingChunk)

// 最终刷新（停止定时器并清空缓冲）
await buffer.flush(update: flushHandler)
```

### 生命周期管理

1. **启动**：首次 `appendContent/appendThinking` 时自动启动定时器
2. **运行**：定时器每 16ms 检查一次，有内容则刷新
3. **停止**：调用 `flush()` 时停止定时器并清空缓冲
4. **清理**：`deinit` 时自动取消定时器

## 测试建议

### 手动测试场景

1. **长文本输出**
   - 提问："用 1000 字详细解释 React Hooks"
   - 观察：文字应该平滑流出，无跳动感

2. **代码块输出**
   - 提问："写一个完整的 Swift SwiftUI 示例"
   - 观察：代码应该逐行流畅显示

3. **中英文混合**
   - 提问："用中英文混合解释计算机网络"
   - 观察：中英文切换应该流畅，无卡顿

### 性能监控

```swift
// 可以在 StreamBuffer 中添加监控代码
private var flushCount = 0
private var totalCharsProcessed = 0

func appendContent(_ chunk: String) {
    totalCharsProcessed += chunk.count
    print("📊 已处理 \(totalCharsProcessed) 字符，共刷新 \(flushCount) 次")
}
```

## 进一步优化方向

### 1. 自适应刷新频率
```swift
// 根据内容流速自动调整刷新频率
private func adaptiveInterval() -> TimeInterval {
    let charsPerSecond = Double(totalCharsProcessed) / elapsedTime
    if charsPerSecond > 1000 {
        return 0.016  // 高速流：60fps
    } else if charsPerSecond > 300 {
        return 0.033  // 中速流：30fps
    } else {
        return 0.050  // 低速流：20fps（节省 CPU）
    }
}
```

### 2. 字符边界智能分割
```swift
// 避免在多字节字符中间切断
private func smartBoundary(_ text: String, maxLength: Int) -> String {
    if text.count <= maxLength { return text }
    
    // 确保不在 emoji 或中文字符中间切断
    let boundary = text.index(text.startIndex, offsetBy: maxLength)
    return String(text[..<boundary])
}
```

### 3. 渲染优化
- 使用 `LazyVStack` 代替 `VStack`（大量消息时）
- 对长消息使用虚拟滚动（只渲染可见区域）
- 缓存 Markdown 解析结果（避免重复解析）

## 总结

这次优化从根本上解决了流式输出卡顿问题：

✅ **从被动检查改为主动定时器**  
✅ **从 12.5fps 提升到 60fps**  
✅ **从 500 字符批量降低到 100 字符**  
✅ **保持与 Claude Code 相同的丝滑体验**  

用户现在应该能感受到**显著的流畅度提升**，文字输出不再跳动，而是平滑流淌！🚀
