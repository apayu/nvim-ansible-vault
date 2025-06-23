#!/bin/bash

echo "🧪 Running basic tests..."

if nvim --headless --cmd "set rtp+=." -c "luafile tests/test_basic.lua" -c "qa" 2>/dev/null; then
    echo "🎉 Tests passed!"
else
    echo "❌ Tests failed!"
    exit 1
fi