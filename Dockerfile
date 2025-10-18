# Stage 1: Build Modelica components
FROM openmodelica/openmodelica:v1.25.0-minimal AS modelica-builder

WORKDIR /build

# Copy Modelica source
COPY modelica-rust-ffi/space-colony-modelica-core/models /build/models

# Build SimpleThermalMVP directly with omc
RUN mkdir -p build/SimpleThermalMVP && \
    cd build/SimpleThermalMVP && \
    cp ../../models/SimpleThermalMVP.mo . && \
    omc --simCodeTarget=C -s SimpleThermalMVP.mo && \
    echo "Modelica component built successfully"

# Stage 2: Build Rust application (based on OpenModelica for libraries)
FROM openmodelica/openmodelica:v1.25.0-minimal AS rust-builder

WORKDIR /build

# Install Rust
RUN apt-get update && apt-get install -y \
    curl \
    build-essential \
    libclang-dev \
    clang \
    pkg-config \
    && curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y \
    && rm -rf /var/lib/apt/lists/*

ENV PATH="/root/.cargo/bin:${PATH}"

# Verify OpenModelica libraries are present
RUN echo "Checking for OpenModelica libraries..." && \
    find /usr -name "libSimulationRuntimeC.*" -o -name "libOpenModelicaRuntimeC.*" 2>/dev/null || \
    echo "Libraries not found in expected location"

# Copy the entire project
COPY . .

# Copy built Modelica components from stage 1
COPY --from=modelica-builder /build/build/SimpleThermalMVP /build/modelica-rust-ffi/space-colony-modelica-core/build/SimpleThermalMVP

# List library directories to debug
RUN echo "=== Library search paths ===" && \
    ls -la /usr/lib/omc/ 2>/dev/null || echo "/usr/lib/omc not found" && \
    ls -la /usr/lib/x86_64-linux-gnu/omc/ 2>/dev/null || echo "/usr/lib/x86_64-linux-gnu/omc not found" && \
    ls -la /usr/lib/aarch64-linux-gnu/omc/ 2>/dev/null || echo "/usr/lib/aarch64-linux-gnu/omc not found"

# Build Rust application
RUN cargo build --release

# Stage 3: Runtime
FROM openmodelica/openmodelica:v1.25.0-minimal

WORKDIR /app

# Copy binary
COPY --from=rust-builder /build/target/release/modbus-server /app/
COPY modbus_config.toml /app/

# OpenModelica libraries should already be in the base image
ENV LD_LIBRARY_PATH=/usr/lib/omc:/usr/lib/x86_64-linux-gnu/omc:/usr/lib/aarch64-linux-gnu/omc:/usr/lib

EXPOSE 5502

CMD ["./modbus-server"]