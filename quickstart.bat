@echo off
setlocal enabledelayedexpansion

echo 🚀 Rio Agent - Quick Start
echo.

REM Check if Rust is installed
where cargo >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo ❌ Rust is not installed. Please install from https://rustup.rs/
    exit /b 1
)

for /f "tokens=*" %%i in ('rustc --version') do set RUST_VERSION=%%i
echo ✅ Rust found: %RUST_VERSION%
echo.

REM Check for ANTHROPIC_API_KEY
if "%ANTHROPIC_API_KEY%"=="" (
    echo ⚠️  ANTHROPIC_API_KEY not set
    echo Please set your API key:
    echo   set ANTHROPIC_API_KEY=sk-ant-...
    echo.
    set /p api_key="Enter your Anthropic API key (or press Enter to skip): "
    if not "!api_key!"=="" (
        set ANTHROPIC_API_KEY=!api_key!
        echo ✅ API key set for this session
    ) else (
        echo ❌ No API key provided. Exiting.
        exit /b 1
    )
) else (
    echo ✅ ANTHROPIC_API_KEY found
)

echo.
echo 📦 Building Rio Agent CLI...
cargo build --release --bin rio-cli

echo.
echo ✅ Build complete!
echo.
echo 📝 Quick test:
echo.

REM Run a simple test
target\release\rio-cli.exe chat "Echo 'Hello from Rio Agent!'"

echo.
echo 🎉 Rio Agent is ready!
echo.
echo Usage examples:
echo   target\release\rio-cli.exe chat "List files in current directory"
echo   target\release\rio-cli.exe sessions
echo   target\release\rio-cli.exe chat --help
echo.

endlocal
