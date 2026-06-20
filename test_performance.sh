#!/bin/bash

# 性能修复验证脚本

echo "🔧 Rio Agent 侧边栏滚动性能修复验证"
echo ""
echo "📋 关键修复："
echo "  1. 移除 SidebarConversationTextDrawingView 的自定义 draw 方法"
echo "  2. 改用 NSTextField 的原生渲染（GPU 加速）"
echo "  3. 启用 NSTableView 和 NSScrollView 的图层支持"
echo "  4. 设置 layerContentsRedrawPolicy = .duringViewResize"
echo ""

# 杀掉旧进程
echo "🛑 关闭旧进程..."
pkill -f "Rio Agent" 2>/dev/null
sleep 1

# 构建 app
echo "🔨 构建应用..."
./build.sh app > /dev/null 2>&1

if [ ! -d "Rio Agent.app" ]; then
    echo "❌ 构建失败"
    exit 1
fi

echo "✅ 构建成功"
echo ""
echo "🚀 启动应用..."
open "Rio Agent.app"
sleep 2

echo ""
echo "📊 测试步骤："
echo "  1. 应用已启动，停留在新对话页面"
echo "  2. 快速上下滑动左侧对话列表"
echo "  3. 观察滚动流畅度"
echo ""
echo "✅ 预期结果："
echo "  • 滚动应该非常流畅，60 FPS"
echo "  • 无卡顿、无掉帧"
echo "  • 与选中对话后的流畅度一致"
echo ""
echo "📈 技术原理："
echo "  • 原问题：每次滚动调用 draw() 重绘所有可见 cell"
echo "  • 解决方案：使用 NSTextField 的 CALayer 硬件加速渲染"
echo "  • 性能提升：从软件渲染改为 GPU 合成"
echo ""
