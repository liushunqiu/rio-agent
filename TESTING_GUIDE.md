# 性能优化测试指南

## 如何验证修复

### 测试步骤
1. 启动应用：`./build.sh run` 或打开 `Rio Agent.app`
2. 确保停留在新对话页面（首页）
3. 快速上下滑动左侧的对话列表
4. 观察滚动流畅度

### 预期结果
✅ **优化后**：滚动应该流畅，60 FPS，无明显卡顿
❌ **优化前**：滚动卡顿，掉帧明显，约 20-30 FPS

### 对比测试
1. 在新对话页面滚动侧边栏（应该流畅）
2. 选择一条对话
3. 再次滚动侧边栏（应该同样流畅）
4. 两种情况下的流畅度应该一致

### 回归测试
- [ ] 对话选中状态显示正确
- [ ] 点击对话能正常切换
- [ ] 删除对话功能正常
- [ ] 新建对话按钮正常
- [ ] 任务运行时的锁定状态正确

## 技术验证（可选）

### 使用 Instruments 测量
```bash
# 1. 构建 app
./build.sh app

# 2. 用 Instruments 打开 Time Profiler
open -a Instruments

# 3. 选择 Time Profiler 模板
# 4. 选择 Rio Agent.app 作为目标
# 5. 开始录制并滚动侧边栏
# 6. 查看 Main Thread 的 CPU 使用率
```

预期：滚动时主线程 CPU 使用率应该显著降低

### 调试输出
如需详细调试信息，可以在代码中添加：
```swift
// 在 SidebarConversationListView.swift 的 update() 方法中
print("Update called - changed: \(idsChanged || selectedChanged || lockStateChanged)")
```

## 已知限制
- 此优化针对新对话页面的滚动性能
- 对话列表很长时（100+ 条）可能仍需进一步优化
- macOS 14.0+ 必需

## 如果仍然卡顿
1. 检查是否有其他应用占用 CPU
2. 重启应用再测试
3. 查看控制台是否有错误日志
4. 提供反馈：对话数量、系统版本、硬件配置
