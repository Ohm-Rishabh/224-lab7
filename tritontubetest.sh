#!/usr/bin/env bash
set -eo pipefail

if pids=$(lsof -ti TCP:8080); then
  echo "Killing leftover servers on 8080: $pids"
  kill -9 $pids || true
  sleep 1
fi

BASE_URL="http://localhost:8080"
METADB="./metadata.db"
STORAGE_DIR="./storage"
VIDEO1="med.mp4"
VIDEO2="med2.mp4"
VIDEO3="med3.mp4"
VIDEO4="med4.mp4"
LOGFILE="server.log"
SERVER_BIN=${SERVER_BIN:-./tritontube_mac}

# Helper: start the TritonTube server in background
start_server() {
  rm -f "$METADB"
  rm -rf "$STORAGE_DIR"
  mkdir -p "$STORAGE_DIR"
  echo "Starting server..."
  go run cmd/web/main.go -port 8080 sqlite "$METADB" fs "$STORAGE_DIR" \
    > "$LOGFILE" 2>&1 &
  SERVER_PID=$!
  sleep 2
}

#start_server() {
  # free up port if needed
#  if pids=$(lsof -ti TCP:8080); then kill -9 $pids; sleep 1; fi

#  rm -f "$METADB"
#  rm -rf "$STORAGE_DIR"
#  mkdir -p "$STORAGE_DIR"
#  echo "Starting server..."
#  "$SERVER_BIN" -port 8080 sqlite "$METADB" fs "$STORAGE_DIR" \
#    > "$LOGFILE" 2>&1 &
#  SERVER_PID=$!
#  sleep 2
#}


# Helper: stop the server
stop_server() {
  if [[ -n "$SERVER_PID" ]]; then
    echo "Stopping server (pid=$SERVER_PID)..."
    # only try to kill if it’s still running
    if kill -0 "$SERVER_PID" 2>/dev/null; then
      kill "$SERVER_PID"
      wait "$SERVER_PID" 2>/dev/null || true
    fi
    unset SERVER_PID
  fi
}


# Helper: do a request and capture both body+status
http_req() {
  # usage: http_req METHOD PATH [curl-options...]
  local method=$1 path=$2; shift 2
  curl -s -w "\n%{http_code}" -X "$method" "$BASE_URL$path" "$@"
}

# Helper: count <a href="/videos/
index_count() {
  curl -s "$BASE_URL/" | grep -o '<a href="/videos/' | wc -l
}

# Enhanced assertion
assert_status() {
  local expect=$1 got=$2 testname=$3 rest="$4"
  if [[ "$got" != "$expect" ]]; then
    echo "FAIL [$testname]: expected HTTP $expect, got $got"
    echo "--- Response body >>>"
    echo "$rest"
    echo "--- Tail of $LOGFILE >>>"
    tail -n20 "$LOGFILE"
    stop_server
    exit 1
  fi
}

echo "=== TEST SUITE START ==="
start_server

# Test 1
echo "-- Test 1: Upload first video"
resp=$(http_req POST /upload -F "file=@$VIDEO1")
body=$(printf "%s\n" "$resp" | sed '$d')
code=$(printf "%s\n" "$resp" | tail -n1)
assert_status 303 "$code" "Test1-upload" "$body"
echo "PASS Test 1 upload"

# Test 1.1: check playback page
code=$(http_req GET /videos/$(basename $VIDEO1 .mp4) | tail -n1)
assert_status 200 "$code" "Test1-videopage"

# Test 1.2: manifest
code=$(http_req GET /content/$(basename $VIDEO1 .mp4)/manifest.mpd | tail -n1)
assert_status 200 "$code" "Test1-manifest"

# Test 1.3: index count
count=$(index_count)
if [[ "$count" -ne 1 ]]; then
  echo "FAIL [Test1-index]: expected 1 video link, got $count"
  stop_server; exit 1
fi
echo "PASS Test 1 lifecycle"

# Test 2
echo "-- Test 2: Upload second video"
resp=$(http_req POST /upload -F "file=@$VIDEO2")
body=$(printf "%s\n" "$resp" | sed '$d')
code=$(printf "%s\n" "$resp" | tail -n1)
assert_status 303 "$code" "Test2-upload" "$body"

code=$(http_req GET /videos/$(basename $VIDEO2 .mp4) | tail -n1)
assert_status 200 "$code" "Test2-videopage"

code=$(http_req GET /content/$(basename $VIDEO2 .mp4)/manifest.mpd | tail -n1)
assert_status 200 "$code" "Test2-manifest"

count=$(index_count)
if [[ "$count" -ne 2 ]]; then
  echo "FAIL [Test2-index]: expected 2 video links, got $count"
  stop_server; exit 1
fi
echo "PASS Test 2"

# Test 4
echo "-- Test 4: Check specific video link"
code=$(http_req GET /videos/$(basename $VIDEO1 .mp4) | tail -n1)
assert_status 200 "$code" "Test4"

# Test 7
echo "-- Test 7: Upload without file"
resp=$(http_req POST /upload)
body=$(printf "%s\n" "$resp" | sed '$d')
code=$(printf "%s\n" "$resp" | tail -n1)
assert_status 400 "$code" "Test7" "$body"

# Test 6
echo "-- Test 6: GET non-existent video"
code=$(http_req GET /videos/does_not_exist | tail -n1)
assert_status 404 "$code" "Test6"

# Restart for persistence
echo "-- Restarting server for persistence tests"
stop_server
echo "Restarting without wiping data..."
go run cmd/web/main.go -port 8080 sqlite "$METADB" fs "$STORAGE_DIR" \
  > "$LOGFILE" 2>&1 &
SERVER_PID=$!
sleep 2

# Test 3
echo "-- Test 3: After restart, index still shows two videos"
count=$(index_count)
if [[ "$count" -ne 2 ]]; then
  echo "FAIL [Test3-index]: expected 2 video links after restart, got $count"
  tail -n20 "$LOGFILE"; stop_server; exit 1
fi
echo "PASS Test 3"

# Test 5
echo "-- Test 5: After restart, manifest still streamable"
code=$(http_req GET /content/$(basename $VIDEO2 .mp4)/manifest.mpd | tail -n1)
assert_status 200 "$code" "Test5"
echo "PASS Test 5"

echo "-- Test 8: Concurrent uploads"

# Prepare temp files and fire off two uploads, capturing their PIDs
u1=$(mktemp); u2=$(mktemp)
curl -s -o /dev/null -w "%{http_code}" \
     -F "file=@$VIDEO3;filename=$(basename $VIDEO3)" \
     "$BASE_URL/upload" > "$u1" & pid_upload1=$!
curl -s -o /dev/null -w "%{http_code}" \
     -F "file=@$VIDEO4;filename=$(basename $VIDEO4)" \
     "$BASE_URL/upload" > "$u2" & pid_upload2=$!

# Wait only for those two uploads
wait $pid_upload1 $pid_upload2

code1=$(<"$u1") && code2=$(<"$u2")
rm "$u1" "$u2"

if [[ "$code1" != "303" || "$code2" != "303" ]]; then
  echo "FAIL [Test8-upload]: expected two 303s, got $code1 and $code2"
  stop_server; exit 1
fi
echo "PASS Test 8a: concurrent uploads succeeded"

# Verify index now shows 4 videos
count=$(index_count)
if [[ "$count" -ne 4 ]]; then
  echo "FAIL [Test8-index]: expected 4 video links, got $count"
  stop_server; exit 1
fi
echo "PASS Test 8b: index shows 4 links"

echo "-- Test 8c: Concurrent streams"

# Fire off two manifest fetches in parallel, capture their PIDs
m1=$(mktemp); m2=$(mktemp)
curl -s -o /dev/null -w "%{http_code}" \
     "$BASE_URL/content/$(basename $VIDEO3 .mp4)/manifest.mpd" > "$m1" & pid_stream1=$!
curl -s -o /dev/null -w "%{http_code}" \
     "$BASE_URL/content/$(basename $VIDEO4 .mp4)/manifest.mpd" > "$m2" & pid_stream2=$!

# Wait only for those two streams
wait $pid_stream1 $pid_stream2

mc1=$(<"$m1") && mc2=$(<"$m2")
rm "$m1" "$m2"

if [[ "$mc1" != "200" || "$mc2" != "200" ]]; then
  echo "FAIL [Test8-stream]: expected two 200s, got $mc1 and $mc2"
  stop_server; exit 1
fi
echo "PASS Test 8c: concurrent streams succeeded"

# Test 4
echo "-- Test 4: Check specific video link"
code=$(http_req GET /videos/$(basename $VIDEO1 .mp4) | tail -n1)
assert_status 200 "$code" "Test4"

# Test 7
echo "-- Test 7: Upload without file"
resp=$(http_req POST /upload)
body=$(printf "%s\n" "$resp" | sed '$d')
code=$(printf "%s\n" "$resp" | tail -n1)
assert_status 400 "$code" "Test7" "$body"

# Test 6
echo "-- Test 6: GET non-existent video"
code=$(http_req GET /videos/does_not_exist | tail -n1)
assert_status 404 "$code" "Test6"

stop_server
echo "=== ALL TESTS PASSED ==="
