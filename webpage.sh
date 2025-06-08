#!/usr/bin/env bash
set -euo pipefail

# Directory for binaries
BIN_DIR=bin
mkdir -p "$BIN_DIR"

# Build binaries
go build -o "$BIN_DIR/storage" ./cmd/storage
go build -o "$BIN_DIR/web" ./cmd/web
go build -o "$BIN_DIR/admin" ./cmd/admin

# Cleanup function to stop servers and free ports
cleanup() {
  echo "Stopping servers..."
  kill $STORAGE_PIDS $WEB_PID 2>/dev/null || true
  wait $STORAGE_PIDS $WEB_PID 2>/dev/null || true
}
trap cleanup EXIT

# Create storage directories
for port in 8090 8091 8092; do
  mkdir -p "storage/$port"
done

# Free any existing processes on required ports
for port in 8080 8081 8090 8091 8092; do
  lsof -ti :$port | xargs -r kill -9 2>/dev/null || true
done

# Start storage servers
STORAGE_PIDS=""
for port in 8090 8091 8092; do
  "$BIN_DIR/storage" -host localhost -port "$port" "storage/$port" > "storage${port}.log" 2>&1 &
  STORAGE_PIDS+="$! "
done

# Give storage servers a moment to initialize
echo "Waiting for storage nodes to start..."
sleep 2

# Start web server (admin gRPC on 8081)
"$BIN_DIR/web" -host localhost -port 8080 sqlite nwtest_metadata.db nw \
  "localhost:8081,localhost:8090,localhost:8091,localhost:8092" > web.log 2>&1 &
WEB_PID=$!

echo "Servers started."
echo "Storage server PIDs: $STORAGE_PIDS"
echo "Web server PID: $WEB_PID"
echo "Open http://localhost:8080 in your browser to view the UI."

# Wait indefinitely to keep the script running
wait
