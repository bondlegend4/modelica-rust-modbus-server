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