# 侧边栏滚动性能优化

## 问题描述
当应用刚打开显示新对话页面时，滑动左侧聊天对话列表会非常卡顿。选择一条对话后，滑动变得丝滑。

## 根本原因
1. **NewChatPage 复杂度高**：包含 30+ 个计算属性和大量条件渲染逻辑
2. **不必要的重绘**：侧边栏滚动时触发整个 ContentView 的刷新，导致 NewChatPage 重新计算所有状态
3. **缺少更新隔离**：SidebarConversationListView 的每次更新都会触发父视图重新计算

## 优化方案

### 1. ContentView 层优化 (ContentView.swift:804-819)
- **添加稳定的 ID**：为 NewChatPage 添加 `.id()` 修饰符，基于关键状态构建 ID
- **禁用隐式动画**：使用 `.transaction` 禁用不必要的动画传播
- **边界裁剪**：为侧边栏列表添加 `.clipped()` 防止渲染溢出

```swift
NewChatPage(...)
    .id("newchat-\(snapshot.primaryModelName)-\(snapshot.canAcceptInput)")
    .transaction { transaction in
        transaction.animation = nil
    }
```

### 2. SidebarConversationListView 优化 (SidebarConversationListView.swift:102-142)
- **早期退出**：在 `update()` 方法中添加变更检测，无变化时直接返回
- **滚动时延迟更新**：利用现有的 `isLiveScrolling` 机制，滚动时只更新 parent 引用
- **细粒度比较**：添加 `itemsDidChange()` 方法逐项比较，避免误判

```swift
// 优化：检查是否有实质性变化
let selectedChanged = selectedID != parent.selectedID
let lockStateChanged = isNavigationLocked != parent.isNavigationLocked

// 如果没有变化，直接返回
guard idsChanged || selectedChanged || lockStateChanged || itemsDidChange(parent.items) else {
    self.parent = parent
    return
}
```

### 3. 视图层边界优化 (ContentView.swift:591-606)
- 为对话列表容器添加 `.clipped()` 严格限定渲染边界
- 防止滚动内容泄漏到外部触发不必要的布局计算

## 性能提升预期
- ✅ **减少 UI 计算**：侧边栏滚动时不再重新计算 NewChatPage 的 30+ 个计算属性
- ✅ **降低帧率损耗**：从卡顿（可能 20-30 FPS）提升到流畅（60 FPS）
- ✅ **保持选择后流畅**：已有对话的流畅体验不受影响

## 测试验证
1. 启动应用，停留在新对话页面
2. 滑动左侧对话列表，观察流畅度
3. 选择一条对话后再滑动，对比流畅度
4. 预期：两种情况下流畅度应该一致

## 技术细节
- **SwiftUI 刷新机制**：`@ObservedObject` 变化会触发整个视图树的 `body` 重新计算
- **NSViewRepresentable 更新**：`updateNSView` 每次父视图刷新都会被调用，需要在此层做变更检测
- **ID 稳定性**：使用 `.id()` 让 SwiftUI 识别视图身份，避免不必要的重建

## 注意事项
- 此优化不改变功能逻辑，仅优化渲染路径
- 保留了原有的实时滚动优化机制（`isLiveScrolling`）
- 兼容现有的动画和过渡效果
