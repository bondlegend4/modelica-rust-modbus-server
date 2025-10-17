FROM rust:1.75-slim as builder

WORKDIR /build

# Install dependencies
RUN apt-get update && apt-get install -y \
    libclang-dev \
    clang \
    && rm -rf /var/lib/apt/lists/*

# Copy source
COPY . .

# Build
RUN cargo build --release

# Runtime image
FROM debian:bookworm-slim

WORKDIR /app

# Copy binary
COPY --from=builder /build/target/release/modbus-server /app/
COPY modbus_config.toml /app/

EXPOSE 5502

CMD ["./modbus-server"]