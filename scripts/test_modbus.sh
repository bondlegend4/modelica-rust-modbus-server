#!/bin/bash

# Integration test script for Modbus server
# Tests basic functionality with modbus-cli

set -e

SERVER="tcp://localhost:5502"
TEMP_REG=40001
HEATER_REG=40002
HEATER_COIL=0

echo "======================================"
echo "Modbus Server Integration Test"
echo "======================================"
echo ""

# Check if modbus-cli is installed
if ! command -v modbus-cli &> /dev/null; then
    echo "❌ modbus-cli not found. Install with:"
    echo "   cargo install modbus-cli"
    exit 1
fi

# Check if server is running
echo "1. Checking if server is running..."
if ! nc -z localhost 5502 2>/dev/null; then
    echo "❌ Server not running on port 5502"
    echo "   Start with: cargo run --release"
    exit 1
fi
echo "✅ Server is running"
echo ""

# Test 1: Read initial temperature
echo "2. Reading initial temperature..."
TEMP=$(modbus-cli read -a $TEMP_REG $SERVER 2>/dev/null | awk '{print $1}')
if [ -z "$TEMP" ]; then
    echo "❌ Failed to read temperature register"
    exit 1
fi
TEMP_K=$(echo "scale=2; $TEMP / 100" | bc)
echo "✅ Temperature: $TEMP_K K (raw: $TEMP)"
echo ""

# Test 2: Read initial heater state
echo "3. Reading initial heater state..."
HEATER=$(modbus-cli read -a $HEATER_REG $SERVER 2>/dev/null | awk '{print $1}')
if [ -z "$HEATER" ]; then
    echo "❌ Failed to read heater state register"
    exit 1
fi
echo "✅ Heater state: $HEATER (0=OFF, 100=ON)"
echo ""

# Test 3: Turn heater ON
echo "4. Turning heater ON..."
if ! modbus-cli write -a $HEATER_COIL true $SERVER &>/dev/null; then
    echo "❌ Failed to write to heater coil"
    exit 1
fi
echo "✅ Heater control coil set to ON"
sleep 1

# Verify heater is on
HEATER=$(modbus-cli read -a $HEATER_REG $SERVER 2>/dev/null | awk '{print $1}')
if [ "$HEATER" -eq 100 ]; then
    echo "✅ Heater state register confirms ON"
else
    echo "⚠️  Heater state is $HEATER (expected 100)"
fi
echo ""

# Test 4: Wait and check temperature increase
echo "5. Waiting 3 seconds for temperature to increase..."
sleep 3
TEMP_NEW=$(modbus-cli read -a $TEMP_REG $SERVER 2>/dev/null | awk '{print $1}')
TEMP_NEW_K=$(echo "scale=2; $TEMP_NEW / 100" | bc)

if [ "$TEMP_NEW" -gt "$TEMP" ]; then
    DELTA=$(echo "scale=2; ($TEMP_NEW - $TEMP) / 100" | bc)
    echo "✅ Temperature increased by $DELTA K"
    echo "   Before: $TEMP_K K → After: $TEMP_NEW_K K"
else
    echo "❌ Temperature did not increase"
    echo "   Before: $TEMP_K K → After: $TEMP_NEW_K K"
    exit 1
fi
echo ""

# Test 5: Turn heater OFF
echo "6. Turning heater OFF..."
if ! modbus-cli write -a $HEATER_COIL false $SERVER &>/dev/null; then
    echo "❌ Failed to write to heater coil"
    exit 1
fi
echo "✅ Heater control coil set to OFF"
sleep 1

# Verify heater is off
HEATER=$(modbus-cli read -a $HEATER_REG $SERVER 2>/dev/null | awk '{print $1}')
if [ "$HEATER" -eq 0 ]; then
    echo "✅ Heater state register confirms OFF"
else
    echo "⚠️  Heater state is $HEATER (expected 0)"
fi
echo ""

# Test 6: Read multiple registers at once
echo "7. Reading both registers simultaneously..."
REGISTERS=$(modbus-cli read -a $TEMP_REG -c 2 $SERVER 2>/dev/null)
if [ -z "$REGISTERS" ]; then
    echo "❌ Failed to read multiple registers"
    exit 1
fi
echo "✅ Multi-register read successful:"
echo "   $REGISTERS"
echo ""

# Test 7: Stress test - rapid reads
echo "8. Stress test: 10 rapid reads..."
FAILURES=0
for i in {1..10}; do
    if ! modbus-cli read -a $TEMP_REG $SERVER &>/dev/null; then
        ((FAILURES++))
    fi
done
if [ $FAILURES -eq 0 ]; then
    echo "✅ All 10 reads successful"
else
    echo "⚠️  $FAILURES out of 10 reads failed"
fi
echo ""

# Summary
echo "======================================"
echo "Test Summary"
echo "======================================"
echo "✅ All critical tests passed"
echo ""
echo "Final state:"
TEMP_FINAL=$(modbus-cli read -a $TEMP_REG $SERVER 2>/dev/null | awk '{print $1}')
HEATER_FINAL=$(modbus-cli read -a $HEATER_REG $SERVER 2>/dev/null | awk '{print $1}')
TEMP_FINAL_K=$(echo "scale=2; $TEMP_FINAL / 100" | bc)
echo "  Temperature: $TEMP_FINAL_K K"
echo "  Heater: $([ "$HEATER_FINAL" -eq 100 ] && echo 'ON' || echo 'OFF')"
echo ""
echo "✅ Modbus server is working correctly!"
