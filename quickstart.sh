#!/bin/bash
set -e

echo "🚀 Rio Agent - Quick Start"
echo ""

# Check if Rust is installed
if ! command -v cargo &> /dev/null; then
    echo "❌ Rust is not installed. Please install from https://rustup.rs/"
    exit 1
fi

echo "✅ Rust found: $(rustc --version)"
echo ""

# Check for ANTHROPIC_API_KEY
if [ -z "$ANTHROPIC_API_KEY" ]; then
    echo "⚠️  ANTHROPIC_API_KEY not set"
    echo "Please set your API key:"
    echo "  export ANTHROPIC_API_KEY=sk-ant-..."
    echo ""
    read -p "Enter your Anthropic API key (or press Enter to skip): " api_key
    if [ -n "$api_key" ]; then
        export ANTHROPIC_API_KEY="$api_key"
        echo "✅ API key set for this session"
    else
        echo "❌ No API key provided. Exiting."
        exit 1
    fi
else
    echo "✅ ANTHROPIC_API_KEY found"
fi

echo ""
echo "📦 Building Rio Agent CLI..."
cargo build --release --bin rio-cli

echo ""
echo "✅ Build complete!"
echo ""
echo "📝 Quick test:"
echo ""

# Run a simple test
./target/release/rio-cli chat "Echo 'Hello from Rio Agent!'"

echo ""
echo "🎉 Rio Agent is ready!"
echo ""
echo "Usage examples:"
echo "  ./target/release/rio-cli chat 'List files in current directory'"
echo "  ./target/release/rio-cli sessions"
echo "  ./target/release/rio-cli chat --help"
echo ""
