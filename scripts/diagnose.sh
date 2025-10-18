#!/bin/bash

echo "🔍 Diagnosing Modbus Connection"
echo "================================"

echo -n "1. Modbus container running? "
if docker ps | grep -q modbus-server; then
    echo "✅ YES"
else
    echo "❌ NO - Start with: docker compose up -d modbus-server"
    exit 1
fi

echo -n "2. Port 5502 accessible from host? "
if nc -zv localhost 5502 2>&1 | grep -q succeeded; then
    echo "✅ YES"
else
    echo "❌ NO"
fi

echo -n "3. OpenPLC container running? "
if docker ps | grep -q openplc; then
    echo "✅ YES"
else
    echo "❌ NO - Start with: docker compose up -d openplc"
    exit 1
fi

echo -n "4. OpenPLC can reach modbus-server? "
if docker exec openplc ping -c 1 -W 1 modbus-server &>/dev/null; then
    echo "✅ YES"
else
    echo "❌ NO - Check docker network configuration"
fi

echo -n "5. Port 5502 open on modbus-server? "
if docker exec openplc nc -zv modbus-server 5502 2>&1 | grep -q succeeded; then
    echo "✅ YES"
else
    echo "❌ NO - Modbus server may not be listening"
fi

echo ""
echo "Testing actual Modbus communication..."
python3 test_connection.py