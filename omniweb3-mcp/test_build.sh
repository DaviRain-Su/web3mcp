#!/bin/bash
set -e

echo "=== Zig 0.16 Build Test ==="
echo

echo "1. Checking Zig version..."
zig version

echo
echo "2. Cleaning previous build..."
rm -rf zig-out .zig-cache

echo
echo "3. Building project..."
zig build

echo
echo "4. Checking binary..."
ls -lh zig-out/bin/omniweb3-mcp
file zig-out/bin/omniweb3-mcp

echo
echo "5. Testing binary execution..."
timeout 1 ./zig-out/bin/omniweb3-mcp < /dev/null 2>&1 || {
    exit_code=$?
    if [ $exit_code -eq 124 ]; then
        echo "✓ Binary runs (timed out waiting for input, as expected)"
    else
        echo "✗ Binary failed with exit code $exit_code"
        exit 1
    fi
}

echo
echo "=== Build Test Complete ==="
echo "✓ All tests passed!"
