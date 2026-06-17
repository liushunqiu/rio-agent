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
    echo "  app       构建 .app（有 RIO_DEVELOPMENT_TEAM 时签名，否则自动回退到本地未签名模式）"
    echo "  app-unsigned  强制构建未签名 .app"
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

# 构建已签名 .app
build_signed_app() {
    echo "正在构建已签名应用包..."
    cd "$(dirname "$0")"
    ./create_app.sh
}

# 构建未签名 .app
build_unsigned_app() {
    echo "正在构建未签名应用包..."
    cd "$(dirname "$0")"
    ./create_app.sh --unsigned
}

# 清理构建产物
clean_project() {
    echo "正在清理构建产物..."
    cd "$(dirname "$0")"
    swift package clean
    rm -rf .build
    rm -rf DerivedData
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
    app)
        build_signed_app
        ;;
    app-unsigned)
        build_unsigned_app
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
