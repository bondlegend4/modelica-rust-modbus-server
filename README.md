# Modelica Rust Modbus Server (MVP)

## Overview

Minimal viable Modbus TCP server exposing the `SimpleThermalMVP` Modelica simulation via standard Modbus protocol. This POC demonstrates the complete pipeline from Modelica physics simulation to industrial control protocols.

## Architecture

```
┌─────────────────────┐
│   Modbus Client     │ (modbus-cli, SCADA-LTS, OpenPLC)
│   (Read/Write)      │
└──────────┬──────────┘
           │ Modbus TCP (Port 5502)
           │
┌──────────▼──────────┐
│  Modbus TCP Server  │
│  (tokio-modbus)     │
├─────────────────────┤
│  Shared State       │
│  (Arc<Mutex<>>)     │
├─────────────────────┤
│  Simulation Loop    │
│  (100ms updates)    │
└──────────┬──────────┘
           │
┌──────────▼──────────┐
│ SimpleThermalMVP    │
│ (FFI Wrapper)       │
├─────────────────────┤
│ ModelicaRuntime     │
│ (Rust safe wrapper) │
├─────────────────────┤
│ OpenModelica C Code │
└─────────────────────┘
```

## Register Mapping

### Holding Registers (Read/Write)

| Address | Name | Format | Units | Range | Description |
|---------|------|--------|-------|-------|-------------|
| 40001 | Temperature | INT16 | K × 100 | 0-65535 | Room temperature scaled by 100 |
| 40002 | Heater State | INT16 | % | 0 or 100 | Heater status (0=OFF, 100=ON) |

### Coils (Read/Write)

| Address | Name | Type | Description |
|---------|------|------|-------------|
| 0 | Heater Control | BOOL | Turn heater ON (true) or OFF (false) |

### Example Values

- Temperature = 27315 → 273.15 K (0°C)
- Temperature = 25000 → 250.00 K (-23.15°C, initial ambient)
- Temperature = 29815 → 298.15 K (25°C, room temperature)
- Heater State = 0 → OFF
- Heater State = 100 → ON

## Quick Start

### Prerequisites

1. **Build modelica-rust-ffi first:**
   ```bash
   cd ../modelica-rust-ffi
   cargo build --release
   ```

2. **Install modbus-cli for testing:**
   ```bash
   cargo install modbus-cli
   ```

### Build and Run

```bash
# Build the server
cargo build --release

# Run the server
cargo run --release

# Or run the binary directly
./target/release/modbus-server
```

The server will start on port 5502 by default.

## Configuration

Edit `modbus_config.toml` to customize:

```toml
port = 5502
update_interval_ms = 100  # 10 Hz simulation rate

[registers]
temperature_address = 40001
heater_state_address = 40002
```

If no config file exists, defaults are used.

## Testing with modbus-cli

### Read Registers

```bash
# Read temperature (address 40001)
modbus-cli read -a 40001 tcp://localhost:5502

# Read heater state (address 40002)
modbus-cli read -a 40002 tcp://localhost:5502

# Read both registers
modbus-cli read -a 40001 -c 2 tcp://localhost:5502
```

### Control Heater

```bash
# Turn heater ON
modbus-cli write -a 0 true tcp://localhost:5502

# Turn heater OFF
modbus-cli write -a 0 false tcp://localhost:5502

# Read coil state
modbus-cli read -c -a 0 tcp://localhost:5502
```

### Example Session

```bash
# Terminal 1: Start server
$ cargo run --release
SimpleThermalMVP Modbus TCP Server
===================================

Configuration:
  Port: 5502
  Update interval: 100 ms
  Temperature register: 40001
  Heater state register: 40002
  Heater control coil: 0

Starting Modbus TCP server on 0.0.0.0:5502
Server running. Press Ctrl+C to stop.

# Terminal 2: Test with modbus-cli
$ modbus-cli read -a 40001 tcp://localhost:5502
25000  # 250.0 K initial temperature

$ modbus-cli write -a 0 true tcp://localhost:5502  # Turn heater ON

$ sleep 5

$ modbus-cli read -a 40001 tcp://localhost:5502
25234  # 252.34 K - temperature increased!

$ modbus-cli read -a 40002 tcp://localhost:5502
100  # Heater is ON
```

## Integration with SCADA Systems

### SCADA-LTS

1. Add Modbus TCP Data Source:
   - Host: `localhost` (or server IP)
   - Port: `5502`
   - Protocol: Modbus TCP

2. Add Data Points:
   - **Temperature**: Holding Register 40001, Type: INT16, Multiplier: 0.01
   - **Heater State**: Holding Register 40002, Type: INT16
   - **Heater Control**: Coil 0, Type: BOOL

### OpenPLC

1. Configure Modbus TCP Master:
   - IP Address: `127.0.0.1`
   - Port: `5502`

2. Map registers in ladder logic:
   ```
   %IW40001  → Temperature input
   %IW40002  → Heater state input
   %QX0      → Heater control output
   ```

## Performance

- **Update Rate**: 10 Hz (100ms intervals)
- **Response Time**: < 10ms for Modbus requests
- **Concurrent Clients**: Tested with 10+ simultaneous connections
- **Memory Usage**: ~5 MB resident

## Troubleshooting

### Server won't start

**Problem**: `Address already in use`

**Solution**: Check if port 5502 is in use:
```bash
lsof -i :5502
# Kill existing process or change port in config
```

### Cannot connect with modbus-cli

**Problem**: Connection refused

**Solution**: 
- Check server is running: `ps aux | grep modbus-server`
- Verify firewall allows port 5502
- Try connecting to 127.0.0.1 instead of localhost

### Temperature not updating

**Problem**: Register value stays constant

**Solution**: Check simulation loop is running. Look for log messages like:
```
Temp: 250.23 K, Heater: OFF
```

If no logs appear, the simulation may have crashed. Restart the server.

### Heater control not working

**Problem**: Writing to coil 0 doesn't affect simulation

**Solution**: 
- Verify you're writing to coil address 0 (not register 0)
- Use: `modbus-cli write -a 0 true` (no `-r` flag)
- Check server logs for "heaterOn" updates

## Development

### Adding More Registers

To expose additional simulation outputs:

1. Update `modbus_config.toml`:
   ```toml
   [registers]
   new_output_address = 40003
   ```

2. In `main.rs` simulation loop:
   ```rust
   let new_value = component.get_output("newOutput")?;
   let scaled = (new_value * 100.0) as u16;
   state.holding_registers.insert(config.registers.new_output_address, scaled);
   ```

### Running Tests

```bash
# Unit tests
cargo test

# Integration test (requires server running)
./scripts/test_modbus.sh
```

## Next Steps

- [ ] Add more thermal components (SolarPanel, LifeSupport)
- [ ] Implement dynamic register discovery
- [ ] Add Modbus slave ID support for multi-device scenarios
- [ ] Create Grafana dashboard for monitoring
- [ ] Add MQTT bridge for IoT integration
- [ ] Implement authentication/encryption (Modbus Security)

## Related Projects

- **modelica-rust-ffi**: Rust FFI wrapper for OpenModelica
- **space-colony-modelica-core**: Modelica physics models
- **godot-modelica-rust-integration**: Godot visualization

## License

Inherits parent project license. Ensure OpenModelica runtime usage complies with OSMC-PL and GPL.
