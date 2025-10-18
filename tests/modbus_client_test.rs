use tokio_modbus::prelude::*;
use tokio_modbus::client::tcp;

#[tokio::test]
async fn test_modbus_server() -> Result<(), Box<dyn std::error::Error>> {
    // Give server time to start if running concurrently
    tokio::time::sleep(tokio::time::Duration::from_millis(100)).await;
    
    // Connect to server
    let socket_addr = "127.0.0.1:5502".parse()?;
    let mut ctx = tcp::connect(socket_addr).await?;
    
    println!("✓ Connected to Modbus server");
    
    // Test 1: Read temperature register (address 100)
    let temp_raw = ctx.read_holding_registers(100, 1).await??;
    let temperature = temp_raw[0] as f64 / 100.0;
    println!("✓ Temperature: {} K (raw: {})", temperature, temp_raw[0]);
    assert!(temperature > 0.0 && temperature < 1000.0, "Temperature out of range");
    
    // Test 2: Read heater state (address 101)
    let heater_state = ctx.read_holding_registers(101, 1).await??;
    println!("✓ Heater state: {} (0=OFF, 100=ON)", heater_state[0]);
    assert!(heater_state[0] == 0 || heater_state[0] == 100, "Invalid heater state");
    
    // Test 3: Turn heater ON (coil 0)
    ctx.write_single_coil(0, true).await??;
    println!("✓ Turned heater ON");
    
    // Wait for state to update
    tokio::time::sleep(tokio::time::Duration::from_millis(200)).await;
    
    // Test 4: Verify heater is on
    let heater_state = ctx.read_holding_registers(101, 1).await??;
    assert_eq!(heater_state[0], 100, "Heater should be ON");
    println!("✓ Heater confirmed ON");
    
    // Test 5: Read temperature again (should be increasing)
    tokio::time::sleep(tokio::time::Duration::from_secs(2)).await;
    let temp_raw_new = ctx.read_holding_registers(100, 1).await??;
    let temperature_new = temp_raw_new[0] as f64 / 100.0;
    println!("✓ Temperature after heating: {} K", temperature_new);
    assert!(temperature_new > temperature, "Temperature should increase with heater on");
    
    // Test 6: Turn heater OFF
    ctx.write_single_coil(0, false).await??;
    println!("✓ Turned heater OFF");
    
    tokio::time::sleep(tokio::time::Duration::from_millis(200)).await;
    
    // Test 7: Verify heater is off
    let heater_state = ctx.read_holding_registers(101, 1).await??;
    assert_eq!(heater_state[0], 0, "Heater should be OFF");
    println!("✓ Heater confirmed OFF");
    
    // Test 8: Read both registers at once (100-101)
    let both = ctx.read_holding_registers(100, 2).await??;
    println!("✓ Multi-register read: temp={}, heater={}", both[0], both[1]);
    
    println!("\n✅ All tests passed!");
    
    Ok(())
}