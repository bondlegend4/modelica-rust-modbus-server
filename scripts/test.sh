#!/bin/bash

echo "🧪 Testing Modbus Server"
echo "======================="
echo ""

# Check if server is running
if ! nc -z localhost 5502 2>/dev/null; then
    echo "❌ Server not running on port 5502"
    echo "   Start with: cargo run"
    exit 1
fi

echo "✅ Server is running on port 5502"
echo ""

# Run tests
echo "Running integration tests..."
cargo test --test modbus_client_test -- --nocapture

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ All tests passed!"
else
    echo ""
    echo "❌ Tests failed"
    exit 1
fi