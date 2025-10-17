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