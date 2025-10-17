# Quick Setup Guide

## Prerequisites

1. **Rust toolchain** (1.70+)
   ```bash
   curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
   ```

2. **OpenModelica** installed at `/Applications/OpenModelica/`
   - Download from: https://openmodelica.org/

3. **modelica-rust-ffi** built and working
   ```bash
   cd ../modelica-rust-ffi
   cargo test  # Should pass
   ```

## Installation

### Step 1: Clone Repository

```bash
git clone https://github.com/bondlegend4/modelica-rust-modbus-server.git
cd modelica-rust-modbus-server
```

### Step 2: Initialize Submodule

```bash
git submodule add ../modelica-rust-ffi modelica-rust-ffi
git submodule update --init --recursive
```

### Step 3: Build

```bash
cargo build --release
```

If build fails with linking errors, check that OpenModelica libraries are accessible:
```bash
ls /Applications/OpenModelica/build_cmake/install_cmake/lib/omc/lib*.dylib
```

### Step 4: Run

```bash
cargo run --release
```

Expected output:
```
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
```

## Testing

### Step 5: Install modbus-cli

```bash
cargo install modbus-cli
```

### Step 6: Basic Test

Open a new terminal:

```bash
# Read temperature
modbus-cli read -a 40001 tcp://localhost:5502

# Should output something like: 25000 (250.0 K)
```

### Step 7: Run Full Test Suite

```bash
chmod +x scripts/test_modbus.sh
./scripts/test_modbus.sh
```

Expected output:
```
======================================
Modbus Server Integration Test
======================================

1. Checking if server is running...
✅ Server is running

2. Reading initial temperature...
✅ Temperature: 250.00 K (raw: 25000)

3. Reading initial heater state...
✅ Heater state: 0 (0=OFF, 100=ON)

4. Turning heater ON...
✅ Heater control coil set to ON
✅ Heater state register confirms ON

5. Waiting 3 seconds for temperature to increase...
✅ Temperature increased by 1.25 K
   Before: 250.00 K → After: 251.25 K

6. Turning heater OFF...
✅ Heater control coil set to OFF
✅ Heater state register confirms OFF

7. Reading both registers simultaneously...
✅ Multi-register read successful

8. Stress test: 10 rapid reads...
✅ All 10 reads successful

======================================
Test Summary
======================================
✅ All critical tests passed
```

## Troubleshooting

### Issue: "Address already in use"

**Cause**: Port 5502 is already in use

**Solution**:
```bash
# Find process using port
lsof -i :5502

# Kill it
kill -9 <PID>

# Or change port in modbus_config.toml
```

### Issue: "Failed to create thermal component"

**Cause**: modelica-rust-ffi not built properly

**Solution**:
```bash
cd modelica-rust-ffi
cargo clean
cargo build --release
cd ../modelica-rust-modbus-server
cargo clean
cargo build --release
```

### Issue: "SimpleThermalMVP.c not found"

**Cause**: Modelica component not compiled

**Solution**:
```bash
cd modelica-rust-ffi/space-colony-modelica-core
./scripts/build_component.sh SimpleThermalMVP
cd ../../modelica-rust-modbus-server
cargo build --release
```

### Issue: "Cannot connect to server"

**Cause**: Server not running or firewall blocking

**Solution**:
```bash
# Check if server is running
ps aux | grep modbus-server

# Check port is open
nc -zv localhost 5502

# Check firewall (macOS)
sudo pfctl -sr | grep 5502

# Allow port if needed
sudo pfctl -f /etc/pf.conf
```

### Issue: Temperature not updating

**Cause**: Simulation loop crashed

**Solution**: Check server logs for error messages. Common causes:
- Invalid timestep
- Numeric overflow
- Memory allocation failure

Restart server with verbose logging:
```bash
RUST_LOG=debug cargo run --release
```

## Configuration Options

Create or edit `modbus_config.toml`:

```toml
# Change server port
port = 5502

# Adjust simulation update rate (Hz)
# 100ms = 10 Hz, 50ms = 20 Hz, 10ms = 100 Hz
update_interval_ms = 100

[registers]
# Customize register addresses
temperature_address = 40001
heater_state_address = 40002
```

## Integration Examples

### Python Client

```python
from pymodbus.client import ModbusTcpClient

client = ModbusTcpClient('localhost', port=5502)
client.connect()

# Read temperature
result = client.read_holding_registers(40001, 1)
temp_scaled = result.registers[0]
temp_k = temp_scaled / 100.0
print(f"Temperature: {temp_k} K")

# Turn heater on
client.write_coil(0, True)

# Read heater state
result = client.read_holding_registers(40002, 1)
heater_state = result.registers[0]
print(f"Heater: {'ON' if heater_state == 100 else 'OFF'}")

client.close()
```

### Node.js Client

```javascript
const ModbusRTU = require("modbus-serial");
const client = new ModbusRTU();

async function run() {
  await client.connectTCP("localhost", { port: 5502 });
  
  // Read temperature
  const temp = await client.readHoldingRegisters(40001, 1);
  console.log(`Temperature: ${temp.data[0] / 100} K`);
  
  // Turn heater on
  await client.writeCoil(0, true);
  
  // Read heater state
  const heater = await client.readHoldingRegisters(40002, 1);
  console.log(`Heater: ${heater.data[0] === 100 ? 'ON' : 'OFF'}`);
  
  client.close();
}

run();
```

### curl (via Modbus REST gateway)

If using a Modbus-to-REST gateway:

```bash
# Read temperature
curl http://localhost:8080/modbus/read/40001

# Write heater control
curl -X POST http://localhost:8080/modbus/write/0 -d '{"value": true}'
```

## Next Steps

1. **Add monitoring**: Set up Grafana dashboard
2. **Add more components**: Solar panels, life support
3. **Deploy to production**: Use Docker Compose
4. **Add security**: Implement authentication
5. **Create HMI**: Build SCADA interface

## Resources

- [Modbus Protocol Specification](http://www.modbus.org/docs/Modbus_Application_Protocol_V1_1b3.pdf)
- [tokio-modbus Documentation](https://docs.rs/tokio-modbus/)
- [modelica-rust-ffi README](../modelica-rust-ffi/README.md)
- [OpenModelica User Guide](https://openmodelica.org/doc/OpenModelicaUsersGuide/latest/)

## Support

For issues or questions:
1. Check the troubleshooting section above
2. Review server logs for error messages
3. Test with `modbus-cli` to isolate issues
4. Open an issue on GitHub with:
   - Operating system
   - Rust version (`rustc --version`)
   - OpenModelica version
   - Complete error message
   - Steps to reproduce
