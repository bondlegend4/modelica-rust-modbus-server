#!/bin/bash

# Startup script for Modbus TCP server
# Handles common setup and provides helpful error messages

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║         Modelica Modbus Server - Startup Script           ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if port is already in use
if lsof -Pi :5502 -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  Warning: Port 5502 is already in use${NC}"
    echo ""
    echo "Existing process:"
    lsof -Pi :5502 -sTCP:LISTEN
    echo ""
    read -p "Kill existing process and continue? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Killing existing process...${NC}"
        lsof -ti :5502 | xargs kill -9
        sleep 1
    else
        echo -e "${RED}Exiting. Please stop the existing server first.${NC}"
        exit 1
    fi
fi

# Check if binary exists
if [ ! -f "target/release/modbus-server" ]; then
    echo -e "${YELLOW}Binary not found. Building...${NC}"
    cargo build --release
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ Build failed${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ Build successful${NC}"
    echo ""
fi

# Check for config file
if [ ! -f "modbus_config.toml" ]; then
    echo -e "${YELLOW}⚠️  Config file not found, using defaults${NC}"
    echo ""
fi

# Display configuration
echo -e "${GREEN}Configuration:${NC}"
if [ -f "modbus_config.toml" ]; then
    echo "  Config file: modbus_config.toml"
    PORT=$(grep "^port" modbus_config.toml | awk '{print $3}')
    INTERVAL=$(grep "^update_interval_ms" modbus_config.toml | awk '{print $3}')
    echo "  Port: ${PORT:-5502}"
    echo "  Update interval: ${INTERVAL:-100} ms"
else
    echo "  Using defaults (port: 5502, interval: 100ms)"
fi
echo ""

# Check dependencies
echo -e "${GREEN}Checking dependencies:${NC}"

# Check if modelica-rust-ffi is built
if [ ! -d "modelica-rust-ffi/target/release" ]; then
    echo -e "${YELLOW}⚠️  modelica-rust-ffi not built${NC}"
    echo "  Building FFI layer..."
    cd modelica-rust-ffi
    cargo build --release
    cd ..
fi
echo -e "${GREEN}✓ FFI layer ready${NC}"

# Check if SimpleThermalMVP is compiled
if [ ! -f "modelica-rust-ffi/space-colony-modelica-core/build/SimpleThermalMVP/SimpleThermalMVP.c" ]; then
    echo -e "${RED}✗ SimpleThermalMVP not compiled${NC}"
    echo ""
    echo "Please build the Modelica component first:"
    echo "  cd modelica-rust-ffi/space-colony-modelica-core"
    echo "  ./scripts/build_component.sh SimpleThermalMVP"
    exit 1
fi
echo -e "${GREEN}✓ SimpleThermalMVP compiled${NC}"
echo ""

# Display help info
echo -e "${BLUE}Quick Reference:${NC}"
echo "  Read temperature:  modbus-cli read -a 40001 tcp://localhost:5502"
echo "  Heater ON:         modbus-cli write -a 0 true tcp://localhost:5502"
echo "  Heater OFF:        modbus-cli write -a 0 false tcp://localhost:5502"
echo "  Monitor:           ./scripts/monitor.sh"
echo "  Test:              ./scripts/test_modbus.sh"
echo ""

# Ask to start
read -p "Start server now? [Y/n] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    echo -e "${GREEN}Starting server...${NC}"
    echo ""
    
    # Run the server
    exec ./target/release/modbus-server
else
    echo -e "${YELLOW}Server not started${NC}"
    echo "To start manually: cargo run --release"
fi
