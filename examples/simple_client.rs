use tokio_modbus::prelude::*;
use tokio_modbus::client::tcp;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    println!("Modbus Client Test");
    println!("==================\n");
    
    // Connect
    let socket_addr = "127.0.0.1:5502".parse()?;
    let mut ctx = tcp::connect(socket_addr).await?;
    println!("Connected to server at {}\n", socket_addr);
    
    loop {
        // Read temperature
        let temp_raw = ctx.read_holding_registers(40001, 1).await??;
        let temperature = temp_raw[0] as f64 / 100.0;
        let temp_c = temperature - 273.15;
        
        // Read heater state
        let heater = ctx.read_holding_registers(40002, 1).await??;
        let heater_on = heater[0] == 100;
        
        println!("Temperature: {:.2} K ({:.2}°C) | Heater: {}", 
                 temperature, temp_c, if heater_on { "ON " } else { "OFF" });
        
        // Simple control logic
        if temp_c < 20.0 && !heater_on {
            println!("  → Turning heater ON");
            ctx.write_single_coil(0, true).await??;
        } else if temp_c > 25.0 && heater_on {
            println!("  → Turning heater OFF");
            ctx.write_single_coil(0, false).await??;
        }
        
        tokio::time::sleep(tokio::time::Duration::from_secs(1)).await;
    }
}