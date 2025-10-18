#!/bin/bash

echo "🧪 Testing Modbus Server in Docker"
echo "==================================="
echo ""

# Check if container is running
if ! docker ps --format '{{.Names}}' | grep -q modelica-modbus-server; then
    echo "❌ Container 'modelica-modbus-server' not running"
    echo "   Start with: docker compose up -d modbus-server"
    exit 1
fi

echo "✅ Container is running"
echo ""

# Check if server port is accessible
if ! nc -z localhost 5502 2>/dev/null; then
    echo "❌ Port 5502 not accessible"
    echo "   Check logs: docker compose logs modbus-server"
    exit 1
fi

echo "✅ Port 5502 is accessible"
echo ""

# Run tests from host against Docker
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