use modelica_rust_ffi::{SimpleThermalComponent, SimulationComponent};
use tokio::time::{interval, Duration};
use tokio_modbus::prelude::*;
use std::collections::HashMap;
use std::net::SocketAddr;
use std::sync::{Arc, Mutex};
use serde::Deserialize;

#[derive(Debug, Deserialize, Clone)]
struct ModbusConfig {
    port: u16,
    update_interval_ms: u64,
    registers: RegisterMapping,
}

#[derive(Debug, Deserialize, Clone)]
struct RegisterMapping {
    temperature_address: u16,
    heater_state_address: u16,
}

impl Default for ModbusConfig {
    fn default() -> Self {
        Self {
            port: 5502,
            update_interval_ms: 100,
            registers: RegisterMapping {
                temperature_address: 40001,
                heater_state_address: 40002,
            },
        }
    }
}

/// Shared state between Modbus server and simulation
struct SharedState {
    /// Holding registers (address -> value)
    holding_registers: HashMap<u16, u16>,
    /// Input registers (address -> value)
    input_registers: HashMap<u16, u16>,
    /// Coils (address -> value)
    coils: HashMap<u16, bool>,
}

impl SharedState {
    fn new() -> Self {
        Self {
            holding_registers: HashMap::new(),
            input_registers: HashMap::new(),
            coils: HashMap::new(),
        }
    }
}

/// Custom Modbus service that reads from shared state
struct ModbusService {
    state: Arc<Mutex<SharedState>>,
}

impl tokio_modbus::server::Service for ModbusService {
    type Request = Request<'static>;  // Add lifetime
    type Response = Response;
    type Exception = Exception;
    type Future = std::pin::Pin<Box<dyn std::future::Future<Output = Result<Response, Exception>> + Send>>;

    fn call(&self, req: Self::Request) -> Self::Future {
        let state = self.state.clone();  // Clone the Arc, not lock yet
        
        Box::pin(async move {
            match req {
                Request::ReadHoldingRegisters(addr, count) => {
                    let state = state.lock().unwrap();  // Lock once here
                    let mut values = Vec::new();
                    for i in 0..count {
                        let register_addr = addr + i;
                        let value = state.holding_registers.get(&register_addr).copied().unwrap_or(0);
                        values.push(value);
                    }
                    Ok(Response::ReadHoldingRegisters(values))
                }
                
                Request::ReadInputRegisters(addr, count) => {
                    let state = state.lock().unwrap();
                    let mut values = Vec::new();
                    for i in 0..count {
                        let register_addr = addr + i;
                        let value = state.input_registers.get(&register_addr).copied().unwrap_or(0);
                        values.push(value);
                    }
                    Ok(Response::ReadInputRegisters(values))
                }
                
                Request::WriteSingleRegister(addr, value) => {
                    let mut state = state.lock().unwrap();  // Mutable lock
                    state.holding_registers.insert(addr, value);
                    Ok(Response::WriteSingleRegister(addr, value))
                }
                
                Request::WriteMultipleRegisters(addr, values) => {
                    let mut state = state.lock().unwrap();
                    for (i, value) in values.iter().enumerate() {
                        state.holding_registers.insert(addr + i as u16, *value);
                    }
                    Ok(Response::WriteMultipleRegisters(addr, values.len() as u16))
                }
                
                Request::ReadCoils(addr, count) => {
                    let state = state.lock().unwrap();
                    let mut values = Vec::new();
                    for i in 0..count {
                        let coil_addr = addr + i;
                        let value = state.coils.get(&coil_addr).copied().unwrap_or(false);
                        values.push(value);
                    }
                    Ok(Response::ReadCoils(values))
                }
                
                Request::WriteSingleCoil(addr, value) => {
                    let mut state = state.lock().unwrap();
                    state.coils.insert(addr, value);
                    Ok(Response::WriteSingleCoil(addr, value))
                }
                
                _ => Err(Exception::IllegalFunction),
            }
        })
    }
}

/// Load configuration from file or use defaults
fn load_config() -> ModbusConfig {
    match std::fs::read_to_string("modbus_config.toml") {
        Ok(contents) => {
            toml::from_str(&contents).unwrap_or_else(|e| {
                eprintln!("Failed to parse config: {}, using defaults", e);
                ModbusConfig::default()
            })
        }
        Err(_) => {
            println!("Config file not found, using defaults");
            ModbusConfig::default()
        }
    }
}

/// Simulation update loop
async fn simulation_loop(
    state: Arc<Mutex<SharedState>>,
    config: ModbusConfig,
) {
    println!("Starting simulation loop...");
    
    // Create thermal component
    let mut component = SimpleThermalComponent::new()
        .expect("Failed to create thermal component");
    
    component.initialize()
        .expect("Failed to initialize component");
    
    println!("Thermal component initialized");
    
    let mut ticker = interval(Duration::from_millis(config.update_interval_ms));
    let dt = config.update_interval_ms as f64 / 1000.0; // Convert to seconds
    
    loop {
        ticker.tick().await;
        
        // Check if heater should be on (read from coil or register)
        let heater_on = {
            let state = state.lock().unwrap();
            // Check coil 0 for heater control
            state.coils.get(&0).copied().unwrap_or(false)
        };
        
        // Update simulation input
        component.set_bool_input("heaterOn", heater_on)
            .expect("Failed to set heater input");
        
        // Step simulation
        component.step(dt)
            .expect("Failed to step simulation");
        
        // Read outputs
        let temperature = component.get_output("temperature")
            .expect("Failed to get temperature");
        let heater_status = component.get_output("heaterStatus")
            .expect("Failed to get heater status");
        
        // Update Modbus registers
        {
            let mut state = state.lock().unwrap();
            
            // Temperature scaled by 100 (e.g., 273.15 K -> 27315)
            let temp_scaled = (temperature * 100.0) as u16;
            state.holding_registers.insert(
                config.registers.temperature_address,
                temp_scaled
            );
            
            // Heater state (0 or 100)
            let heater_scaled = (heater_status * 100.0) as u16;
            state.holding_registers.insert(
                config.registers.heater_state_address,
                heater_scaled
            );
        }
        
        // Log every 10 seconds
        if ticker.period().as_secs() % 10 == 0 {
            println!(
                "Temp: {:.2} K, Heater: {}",
                temperature,
                if heater_on { "ON" } else { "OFF" }
            );
        }
    }
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    println!("SimpleThermalMVP Modbus TCP Server");
    println!("===================================");
    
    // Load configuration
    let config = load_config();
    println!("\nConfiguration:");
    println!("  Port: {}", config.port);
    println!("  Update interval: {} ms", config.update_interval_ms);
    println!("  Temperature register: {}", config.registers.temperature_address);
    println!("  Heater state register: {}", config.registers.heater_state_address);
    println!("  Heater control coil: 0");
    
    // Create shared state
    let state = Arc::new(Mutex::new(SharedState::new()));
    
    // Initialize registers to zero
    {
        let mut s = state.lock().unwrap();
        s.holding_registers.insert(config.registers.temperature_address, 25000); // 250.0 K
        s.holding_registers.insert(config.registers.heater_state_address, 0);
        s.coils.insert(0, false);
    }
    
    // Start simulation loop in background
    let sim_state = state.clone();
    let sim_config = config.clone();
    tokio::spawn(async move {
        simulation_loop(sim_state, sim_config).await;
    });
    
    // Start Modbus server
    let socket_addr: SocketAddr = format!("0.0.0.0:{}", config.port).parse()?;
    println!("\nStarting Modbus TCP server on {}", socket_addr);
    println!("\nRegister Mapping:");
    println!("  Register {}: Temperature (K × 100)", config.registers.temperature_address);
    println!("  Register {}: Heater State (0=OFF, 100=ON)", config.registers.heater_state_address);
    println!("  Coil 0: Heater Control (write TRUE=ON, FALSE=OFF)");
    println!("\nTesting:");
    println!("  cargo test --test modbus_client_test -- --nocapture");
    println!("  cargo run --example simple_client");
    println!("\nServer running. Press Ctrl+C to stop.\n");
    let listener = tokio::net::TcpListener::bind(socket_addr).await?;

    let server = tokio_modbus::server::tcp::Server::new(listener);
    
    let state_clone = state.clone();
    server
        .serve(
            &move |stream, _socket_addr| {  // stream first, then socket_addr
                let state = state_clone.clone();
                async move {
                    let service = ModbusService { state };
                    Ok(Some((service, stream)))
                }
            },
            &|err| {
                eprintln!("Modbus connection error: {:?}", err);
            },
        )
        .await?;
    
    Ok(())
}
