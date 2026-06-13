#!/bin/bash

# Rio Agent 构建脚本

set -e

echo "=== Rio Agent 构建脚本 ==="

# 检查是否安装了 Xcode
if ! command -v xcodebuild &> /dev/null; then
    echo "错误: 未找到 Xcode。请先安装 Xcode。"
    exit 1
fi

# 显示帮助
show_help() {
    echo "用法: ./build.sh [命令]"
    echo ""
    echo "命令:"
    echo "  build     构建项目"
    echo "  run       构建并运行项目"
    echo "  clean     清理构建产物"
    echo "  test      运行测试"
    echo "  help      显示此帮助信息"
    echo ""
}

# 构建项目
build_project() {
    echo "正在构建 Rio Agent..."
    cd "$(dirname "$0")"
    swift build
    echo "构建完成！"
}

# 运行项目
run_project() {
    echo "正在运行 Rio Agent..."
    cd "$(dirname "$0")"
    swift run
}

# 清理构建产物
clean_project() {
    echo "正在清理构建产物..."
    cd "$(dirname "$0")"
    swift package clean
    rm -rf .build
    echo "清理完成！"
}

# 运行测试
run_tests() {
    echo "正在运行测试..."
    cd "$(dirname "$0")"
    swift test
    echo "测试完成！"
}

# 主逻辑
case "${1:-help}" in
    build)
        build_project
        ;;
    run)
        run_project
        ;;
    clean)
        clean_project
        ;;
    test)
        run_tests
        ;;
    help|*)
        show_help
        ;;
esac
