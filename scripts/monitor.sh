#!/bin/bash

# Real-time monitoring script for Modbus server
# Displays temperature and heater state in a live dashboard

SERVER="tcp://localhost:5502"
TEMP_REG=40001
HEATER_REG=40002

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Check dependencies
if ! command -v modbus-cli &> /dev/null; then
    echo "Error: modbus-cli not found"
    echo "Install with: cargo install modbus-cli"
    exit 1
fi

# Check server connectivity
if ! nc -z localhost 5502 2>/dev/null; then
    echo "Error: Cannot connect to server on port 5502"
    echo "Start server with: cargo run --release"
    exit 1
fi

# Clear screen and hide cursor
clear
tput civis

# Trap Ctrl+C to restore cursor
trap 'tput cnorm; exit' INT TERM

# Initialize variables
MAX_TEMP=0
MIN_TEMP=99999
START_TIME=$(date +%s)

echo -e "${BOLD}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║         Modelica Modbus Server - Live Monitor             ║${NC}"
echo -e "${BOLD}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Main monitoring loop
while true; do
    # Read temperature
    TEMP_RAW=$(modbus-cli read -a $TEMP_REG $SERVER 2>/dev/null | awk '{print $1}')
    if [ -z "$TEMP_RAW" ]; then
        echo -e "${RED}✗ Failed to read temperature${NC}"
        sleep 1
        continue
    fi
    
    # Read heater state
    HEATER_RAW=$(modbus-cli read -a $HEATER_REG $SERVER 2>/dev/null | awk '{print $1}')
    if [ -z "$HEATER_RAW" ]; then
        echo -e "${RED}✗ Failed to read heater state${NC}"
        sleep 1
        continue
    fi
    
    # Convert temperature (scaled by 100)
    TEMP_K=$(echo "scale=2; $TEMP_RAW / 100" | bc)
    TEMP_C=$(echo "scale=2; $TEMP_K - 273.15" | bc)
    TEMP_F=$(echo "scale=2; $TEMP_C * 9/5 + 32" | bc)
    
    # Update min/max
    if [ "$TEMP_RAW" -gt "$MAX_TEMP" ]; then
        MAX_TEMP=$TEMP_RAW
    fi
    if [ "$TEMP_RAW" -lt "$MIN_TEMP" ]; then
        MIN_TEMP=$TEMP_RAW
    fi
    
    # Calculate uptime
    CURRENT_TIME=$(date +%s)
    UPTIME=$((CURRENT_TIME - START_TIME))
    UPTIME_MIN=$((UPTIME / 60))
    UPTIME_SEC=$((UPTIME % 60))
    
    # Heater status
    if [ "$HEATER_RAW" -eq 100 ]; then
        HEATER_STATUS="${GREEN}● ON ${NC}"
        HEATER_EMOJI="🔥"
    else
        HEATER_STATUS="${RED}● OFF${NC}"
        HEATER_EMOJI="❄️"
    fi
    
    # Temperature bar graph (0-400K range)
    BAR_WIDTH=40
    BAR_VALUE=$(echo "scale=0; ($TEMP_RAW - 20000) * $BAR_WIDTH / 20000" | bc)
    if [ "$BAR_VALUE" -lt 0 ]; then BAR_VALUE=0; fi
    if [ "$BAR_VALUE" -gt "$BAR_WIDTH" ]; then BAR_VALUE=$BAR_WIDTH; fi
    
    BAR=""
    for ((i=0; i<BAR_VALUE; i++)); do
        BAR="${BAR}█"
    done
    for ((i=BAR_VALUE; i<BAR_WIDTH; i++)); do
        BAR="${BAR}░"
    done
    
    # Temperature color coding
    if (( $(echo "$TEMP_K < 260" | bc -l) )); then
        TEMP_COLOR=$BLUE
    elif (( $(echo "$TEMP_K < 280" | bc -l) )); then
        TEMP_COLOR=$GREEN
    elif (( $(echo "$TEMP_K < 300" | bc -l) )); then
        TEMP_COLOR=$YELLOW
    else
        TEMP_COLOR=$RED
    fi
    
    # Move cursor to top of data area
    tput cup 4 0
    
    # Display data
    echo -e "${BOLD}┌─ Temperature ────────────────────────────────────────────┐${NC}"
    echo -e "│  ${TEMP_COLOR}${BOLD}${TEMP_K} K${NC}  |  ${TEMP_C}°C  |  ${TEMP_F}°F        "
    echo -e "│  ${BAR}  "
    echo -e "${BOLD}└──────────────────────────────────────────────────────────┘${NC}"
    echo ""
    
    echo -e "${BOLD}┌─ Heater Status ──────────────────────────────────────────┐${NC}"
    echo -e "│  ${HEATER_EMOJI}  ${HEATER_STATUS}                                          "
    echo -e "${BOLD}└──────────────────────────────────────────────────────────┘${NC}"
    echo ""
    
    echo -e "${BOLD}┌─ Statistics ─────────────────────────────────────────────┐${NC}"
    printf "│  Min: %.2f K  |  Max: %.2f K  |  Range: %.2f K   \n" \
        $(echo "scale=2; $MIN_TEMP / 100" | bc) \
        $(echo "scale=2; $MAX_TEMP / 100" | bc) \
        $(echo "scale=2; ($MAX_TEMP - $MIN_TEMP) / 100" | bc)
    echo -e "${BOLD}└──────────────────────────────────────────────────────────┘${NC}"
    echo ""
    
    echo -e "${BOLD}┌─ Server Info ────────────────────────────────────────────┐${NC}"
    printf "│  Uptime: %02d:%02d  |  Port: 5502  |  Update: 10 Hz      \n" \
        $UPTIME_MIN $UPTIME_SEC
    echo -e "${BOLD}└──────────────────────────────────────────────────────────┘${NC}"
    echo ""
    
    echo -e "${BOLD}Controls:${NC}"
    echo -e "  ${GREEN}Heater ON:${NC}   modbus-cli write -a 0 true tcp://localhost:5502"
    echo -e "  ${RED}Heater OFF:${NC}  modbus-cli write -a 0 false tcp://localhost:5502"
    echo -e "  ${YELLOW}Press Ctrl+C to exit${NC}"
    
    # Wait 1 second
    sleep 1
done
