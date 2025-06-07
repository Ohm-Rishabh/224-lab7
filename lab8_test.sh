#!/usr/bin/env bash
set -euo pipefail

BASE_URL="http://localhost:8080"
ADMIN_ADDR="localhost:8081"
METADB="./nwtest_metadata.db"

cleanup() {
  kill $WEB_PID $S1_PID $S2_PID $S3_PID 2>/dev/null || true
  wait $WEB_PID $S1_PID $S2_PID $S3_PID 2>/dev/null || true
}

# Kill any existing processes on our test ports
for port in 8080 8081 8090 8091 8092; do
  lsof -ti :$port | xargs kill -9 2>/dev/null || true
done

trap cleanup EXIT

rm -f "$METADB"
rm -rf storage/8090 storage/8091 storage/8092
mkdir -p storage/8090 storage/8091 storage/8092

go run ./cmd/storage -host localhost -port 8090 ./storage/8090 > storage8090.log 2>&1 &
S1_PID=$!
go run ./cmd/storage -host localhost -port 8091 ./storage/8091 > storage8091.log 2>&1 &
S2_PID=$!
go run ./cmd/storage -host localhost -port 8092 ./storage/8092 > storage8092.log 2>&1 &
S3_PID=$!

# wait a moment for servers to start
sleep 2

go run ./cmd/web -port 8080 sqlite "$METADB" nw "$ADMIN_ADDR,localhost:8090,localhost:8091" > web.log 2>&1 &
WEB_PID=$!
sleep 3

VIDEO1="BULBASAUR.mp4"
VIDEO2="b.mp4"
VIDEO3="PIKACHU.mp4"

# upload first video
resp=$(curl -s -w "\n%{http_code}" -F "file=@$VIDEO1" "$BASE_URL/upload")
code=$(echo "$resp" | tail -n1)
if [ "$code" != "303" ]; then
  echo "FAIL: upload video1"
  exit 1
fi

resp=$(curl -s -w "\n%{http_code}" -F "file=@$VIDEO2" "$BASE_URL/upload")
code=$(echo "$resp" | tail -n1)
if [ "$code" != "303" ]; then
  echo "FAIL: upload video1"
  exit 1
fi

resp=$(curl -s -w "\n%{http_code}" -F "file=@$VIDEO3" "$BASE_URL/upload")
code=$(echo "$resp" | tail -n1)
if [ "$code" != "303" ]; then
  echo "FAIL: upload video1"
  exit 1
fi

# manifest accessible
code=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/content/${VIDEO1%.mp4}/manifest.mpd")
if [ "$code" != "200" ]; then
  echo "FAIL: manifest not accessible after upload"
  exit 1
fi

# list nodes
list_output=$(go run ./cmd/admin list "$ADMIN_ADDR")
if ! echo "$list_output" | grep -q "localhost:8090"; then
  echo "FAIL: expected node 8090 in list"
  exit 1
fi

# remove a node
go run ./cmd/admin remove "$ADMIN_ADDR" localhost:8090 >/tmp/remove.log
list_output=$(go run ./cmd/admin list "$ADMIN_ADDR")
if echo "$list_output" | grep -q "localhost:8090"; then
  echo "FAIL: node not removed"
  exit 1
fi

# video still accessible after removal
code=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/content/${VIDEO1%.mp4}/manifest.mpd")
if [ "$code" != "200" ]; then
  echo "FAIL: manifest unavailable after node removal"
  exit 1
fi

# add node back
go run ./cmd/admin add "$ADMIN_ADDR" localhost:8092 >/tmp/add.log
list_output=$(go run ./cmd/admin list "$ADMIN_ADDR")
if ! echo "$list_output" | grep -q "localhost:8092"; then
  echo "FAIL: node not added"
  exit 1
fi

# index shows two videos
count=$(curl -s "$BASE_URL/" | grep -o '<a href="/videos/' | wc -l)
if [ "$count" -ne 2 ]; then
  echo "FAIL: expected 2 videos, got $count"
  exit 1
fi

echo "ALL TESTS PASSED"