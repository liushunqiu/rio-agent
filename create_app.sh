#!/bin/bash

set -euo pipefail

APP_NAME="Rio Agent"
SCHEME="RioAgent"
PROJECT_FILE="RioAgent.xcodeproj"
PROJECT_SPEC="project.yml"
PROJECT_PBXPROJ="$PROJECT_FILE/project.pbxproj"
CONFIGURATION="${RIO_CONFIGURATION:-Release}"
DERIVED_DATA_DIR="${RIO_DERIVED_DATA_DIR:-DerivedData/RioAgent}"
OUTPUT_APP_PATH="${RIO_OUTPUT_APP_PATH:-$APP_NAME.app}"
TEAM_ID="${RIO_DEVELOPMENT_TEAM:-${DEVELOPMENT_TEAM:-}}"
CODE_SIGN_IDENTITY="${RIO_CODE_SIGN_IDENTITY:-}"
UNSIGNED_BUILD=0

show_help() {
    cat <<'EOF'
用法: ./create_app.sh [--debug|--release] [--unsigned]

默认行为:
  - 若设置了 RIO_DEVELOPMENT_TEAM，则使用 Xcode 构建已签名 .app，保持稳定的应用身份
  - 若未设置，则自动回退到未签名本地开发包
  - 未签名包会禁用 Keychain，改用本地 UserDefaults 存储 API Key，以避免重复密码弹窗

可选参数:
  --debug       使用 Debug 配置
  --release     使用 Release 配置（默认）
  --unsigned    生成未签名开发包（仍可能重复触发密码/授权弹窗）
  --help        显示帮助

环境变量:
  RIO_DEVELOPMENT_TEAM   Apple Developer Team ID；设置后启用稳定签名
  RIO_CODE_SIGN_IDENTITY 可选，默认由 Xcode 自动选择
  RIO_DERIVED_DATA_DIR   可选，默认 DerivedData/RioAgent
  RIO_OUTPUT_APP_PATH    可选，默认 ./Rio Agent.app
  RIO_SWIFTPM_HOME       可选，未签名构建时的本地 SwiftPM HOME

示例:
  RIO_DEVELOPMENT_TEAM=ABCDE12345 ./create_app.sh
  RIO_DEVELOPMENT_TEAM=ABCDE12345 ./create_app.sh --debug
  ./create_app.sh --unsigned
EOF
}

ensure_xcode_project() {
    local should_generate=0

    if [[ ! -d "$PROJECT_FILE" || ! -f "$PROJECT_PBXPROJ" ]]; then
        should_generate=1
    elif [[ "$PROJECT_SPEC" -nt "$PROJECT_PBXPROJ" ]]; then
        should_generate=1
    fi

    if [[ $should_generate -eq 0 ]]; then
        return
    fi

    if ! command -v xcodegen >/dev/null 2>&1; then
        echo "错误: 需要 xcodegen 来生成最新的 Xcode 项目。"
        echo "请先安装 xcodegen，或先在本机生成 RioAgent.xcodeproj。"
        exit 1
    fi

    echo "检测到 Xcode 项目需要更新，正在重新生成..."
    xcodegen generate
}

copy_signed_app_bundle() {
    local built_app="$1"

    rm -rf "$OUTPUT_APP_PATH"
    ditto "$built_app" "$OUTPUT_APP_PATH"
}

build_signed_app() {
    if [[ -z "$TEAM_ID" ]]; then
        echo "未设置 RIO_DEVELOPMENT_TEAM，回退到未签名本地开发包。"
        echo ""
        echo "如需稳定签名，请先执行："
        echo "  export RIO_DEVELOPMENT_TEAM=你的TeamID"
        echo "  ./create_app.sh"
        echo ""
        build_unsigned_app
        return
    fi

    ensure_xcode_project

    local xcodebuild_args=(
        -project "$PROJECT_FILE"
        -scheme "$SCHEME"
        -configuration "$CONFIGURATION"
        -derivedDataPath "$DERIVED_DATA_DIR"
        -destination "platform=macOS"
        build
        CODE_SIGN_STYLE=Automatic
        DEVELOPMENT_TEAM="$TEAM_ID"
    )

    if [[ -n "$CODE_SIGN_IDENTITY" ]]; then
        xcodebuild_args+=("CODE_SIGN_IDENTITY=$CODE_SIGN_IDENTITY")
    fi

    echo "正在构建已签名应用..."
    xcodebuild "${xcodebuild_args[@]}"

    local built_app="$DERIVED_DATA_DIR/Build/Products/$CONFIGURATION/$APP_NAME.app"
    if [[ ! -d "$built_app" ]]; then
        echo "错误: 未找到构建产物: $built_app"
        exit 1
    fi

    copy_signed_app_bundle "$built_app"

    echo ""
    echo "已创建已签名应用: $OUTPUT_APP_PATH"
    echo "建议首次启动时在 Keychain 提示中选择“总是允许”。"
    echo "运行方式:"
    echo "  open \"$OUTPUT_APP_PATH\""
}

build_unsigned_app() {
    local app_dir="$OUTPUT_APP_PATH"
    local contents_dir="$app_dir/Contents"
    local macos_dir="$contents_dir/MacOS"
    local resources_dir="$contents_dir/Resources"
    local swiftpm_home="${RIO_SWIFTPM_HOME:-$PWD/.swiftpm-home}"

    echo "正在构建未签名开发包..."
    mkdir -p "$swiftpm_home"
    HOME="$swiftpm_home" swift build -c release

    rm -rf "$app_dir"
    mkdir -p "$macos_dir" "$resources_dir"
    cp .build/release/RioAgent "$macos_dir/$APP_NAME"

    cat > "$contents_dir/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>Rio Agent</string>
    <key>CFBundleIdentifier</key>
    <string>com.rioagent.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Rio Agent</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>RIOUnsignedBuild</key>
    <true/>
</dict>
</plist>
EOF

    echo ""
    echo "已创建未签名开发包: $app_dir"
    echo "注意: 当前未签名包已禁用 Keychain，API Key 会改存到本地 UserDefaults，以避免重复密码弹窗。"
    echo "如需稳定签名并恢复 Keychain，请改用："
    echo "  RIO_DEVELOPMENT_TEAM=你的TeamID ./create_app.sh"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --debug)
            CONFIGURATION="Debug"
            ;;
        --release)
            CONFIGURATION="Release"
            ;;
        --unsigned)
            UNSIGNED_BUILD=1
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            echo "错误: 未知参数 $1"
            echo ""
            show_help
            exit 1
            ;;
    esac
    shift
done

cd "$(dirname "$0")"

echo "=== Rio Agent 应用打包 ==="

if [[ $UNSIGNED_BUILD -eq 1 ]]; then
    build_unsigned_app
else
    build_signed_app
fi
