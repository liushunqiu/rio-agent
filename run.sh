#!/bin/bash

# Rio Agent 运行脚本

set -e

echo "正在启动 Rio Agent..."
echo ""

# 构建项目
echo "构建中..."
swift build 2>&1 | grep -v "warning:"

# 获取构建产物路径
PRODUCT_PATH=".build/debug/RioAgent"

if [ ! -f "$PRODUCT_PATH" ]; then
    echo "错误: 构建产物不存在"
    exit 1
fi

echo "启动应用..."
echo ""

# 运行应用
"$PRODUCT_PATH"
