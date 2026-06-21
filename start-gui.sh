#!/bin/bash
# Tauri GUI 开发启动脚本

set -e

echo "🚀 启动 Rio Agent Tauri GUI..."
echo ""

# 检查环境变量
if [ -z "$ANTHROPIC_API_KEY" ]; then
    echo "⚠️  警告: ANTHROPIC_API_KEY 未设置"
    echo "   请设置环境变量: export ANTHROPIC_API_KEY='your-key'"
    echo ""
fi

# 进入 UI 目录
cd "$(dirname "$0")/rio-agent-ui"

# 启动开发服务器
echo "📦 安装依赖（如需要）..."
npm install --silent

echo ""
echo "🎨 启动 Tauri 开发模式..."
echo "   前端: http://localhost:5173"
echo "   后端: Rust (rio-core + 所有 crates)"
echo ""

npm run tauri:dev
