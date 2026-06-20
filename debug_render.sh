#!/bin/bash

echo "🔍 测试 NewChatPage 渲染性能"
echo "================================"
echo ""

# 杀掉旧进程
pkill -f "Rio Agent" 2>/dev/null
sleep 1

# 清空系统日志
log erase --all 2>/dev/null

echo "🚀 启动应用（观察控制台输出）..."
./.build/debug/RioAgent 2>&1 | grep -E "⚠️|🔄|NewChatPage|渲染"
