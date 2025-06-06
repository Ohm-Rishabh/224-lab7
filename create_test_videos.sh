#!/bin/bash

# TritonTube Test Script
# Tests all 7 test cases as described in the requirements

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
SERVER_HOST="localhost"
SERVER_PORT="8080"
BASE_URL="http://${SERVER_HOST}:${SERVER_PORT}"
SERVER_CMD="go run ./cmd/web/main.go -port ${SERVER_PORT} sqlite ./test_metadata.db fs ./test_storage"
SERVER_PID=""

# Test counter
TESTS_PASSED=0
TESTS_FAILED=0

# Function to print test results
print_result() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✓ $2${NC}"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗ $2${NC}"
        ((TESTS_FAILED++))
    fi
}

# Function to start the server
start_server() {
    echo -e "${YELLOW}Starting TritonTube server...${NC}"
    
    # Clean up test data from previous runs
    rm -rf ./test_storage
    rm -f ./test_metadata.db
    mkdir -p ./test_storage
    
    # Start server in background
    $SERVER_CMD > server.log 2>&1 &
    SERVER_PID=$!
    
    # Wait for server to start
    sleep 3
    
    # Check if server is running
    if ! ps -p $SERVER_PID > /dev/null; then
        echo -e "${RED}Failed to start server! Check server.log for details${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}Server started with PID: $SERVER_PID${NC}"
}

# Function to stop the server
stop_server() {
    if [ ! -z "$SERVER_PID" ]; then
        echo -e "${YELLOW}Stopping server (PID: $SERVER_PID)...${NC}"
        kill $SERVER_PID 2>/dev/null
        wait $SERVER_PID 2>/dev/null
        SERVER_PID=""
        sleep 1
    fi
}

# Function to check if video files exist
check_video_files() {
    local missing_files=()
    
    for video in "small.mp4" "small2.mp4"; do
        if [ ! -f "$video" ]; then
            missing_files+=("$video")
        fi
    done
    
    if [ ${#missing_files[@]} -ne 0 ]; then
        echo -e "${RED}Error: Missing required video files: ${missing_files[*]}${NC}"
        echo -e "${YELLOW}Please ensure you have small.mp4 and small2.mp4 in the current directory${NC}"
        echo -e "${YELLOW}You can download sample videos from: https://sample-videos.com/download-sample-mp4.php${NC}"
        exit 1
    fi
}

# Cleanup function
cleanup() {
    stop_server
    rm -f server.log response.txt
}

# Set trap to cleanup on exit
trap cleanup EXIT

# Check for required video files
check_video_files

echo -e "${YELLOW}=== TritonTube Test Suite ===${NC}"
echo

# Start the server
start_server

# Test 1: Upload first Video
echo -e "${YELLOW}Test 1: Upload first Video${NC}"

# Upload the video
response=$(curl -s -o response.txt -w "%{http_code}" -L -X POST -F "file=@small.mp4" ${BASE_URL}/upload)
if [ "$response" = "200" ]; then
    # Check if we were redirected to homepage (303 then 200)
    curl_output=$(curl -s -o /dev/null -w "%{http_code}\n%{redirect_url}" -X POST -F "file=@small.mp4" ${BASE_URL}/upload)
    if [[ "$curl_output" == *"303"* ]]; then
        print_result 0 "Upload returned 303 redirect"
    else
        print_result 1 "Upload did not return 303 redirect"
    fi
else
    print_result 1 "Upload failed with status: $response"
fi

# Check video page
response=$(curl -s -o /dev/null -w "%{http_code}" ${BASE_URL}/videos/small)
[ "$response" = "200" ] && print_result 0 "Video page accessible (200 OK)" || print_result 1 "Video page not accessible: $response"

# Check DASH manifest
response=$(curl -s -o /dev/null -w "%{http_code}" ${BASE_URL}/content/small/manifest.mpd)
[ "$response" = "200" ] && print_result 0 "DASH manifest accessible" || print_result 1 "DASH manifest not accessible: $response"

# Check homepage has one video
video_count=$(curl -s ${BASE_URL}/ | grep -o 'href="/videos/[^"]*"' | wc -l)
[ "$video_count" -eq 1 ] && print_result 0 "Homepage shows 1 video" || print_result 1 "Homepage shows $video_count videos (expected 1)"

echo

# Test 2: Upload second Video
echo -e "${YELLOW}Test 2: Upload second Video${NC}"

# Upload second video
response=$(curl -s -o response.txt -w "%{http_code}" -L -X POST -F "file=@small2.mp4" ${BASE_URL}/upload)
if [ "$response" = "200" ]; then
    print_result 0 "Second video uploaded successfully"
else
    print_result 1 "Second video upload failed: $response"
fi

# Check second video page
response=$(curl -s -o /dev/null -w "%{http_code}" ${BASE_URL}/videos/small2)
[ "$response" = "200" ] && print_result 0 "Second video page accessible" || print_result 1 "Second video page not accessible: $response"

# Check second video DASH manifest
response=$(curl -s -o /dev/null -w "%{http_code}" ${BASE_URL}/content/small2/manifest.mpd)
[ "$response" = "200" ] && print_result 0 "Second video DASH manifest accessible" || print_result 1 "Second video DASH manifest not accessible: $response"

# Check homepage has two videos
video_count=$(curl -s ${BASE_URL}/ | grep -o 'href="/videos/[^"]*"' | wc -l)
[ "$video_count" -eq 2 ] && print_result 0 "Homepage shows 2 videos" || print_result 1 "Homepage shows $video_count videos (expected 2)"

echo

# Test 3: Restart server, check video list persists
echo -e "${YELLOW}Test 3: Restart server, check video list persists${NC}"

# Stop server
stop_server

# Start server again
start_server

# Check homepage still has two videos
video_count=$(curl -s ${BASE_URL}/ | grep -o 'href="/videos/[^"]*"' | wc -l)
[ "$video_count" -eq 2 ] && print_result 0 "Homepage still shows 2 videos after restart" || print_result 1 "Homepage shows $video_count videos after restart (expected 2)"

echo

# Test 4: Check specific video link
echo -e "${YELLOW}Test 4: Check Video link [small]${NC}"

response=$(curl -s -o /dev/null -w "%{http_code}" ${BASE_URL}/videos/small)
[ "$response" = "200" ] && print_result 0 "Video 'small' accessible (200 OK)" || print_result 1 "Video 'small' not accessible: $response"

echo

# Test 5: Restart server, stream video
echo -e "${YELLOW}Test 5: Restart server, stream video [small]${NC}"

# Stop server
stop_server

# Start server again
start_server

# Check if video is still streamable
response=$(curl -s -o /dev/null -w "%{http_code}" ${BASE_URL}/content/small/manifest.mpd)
[ "$response" = "200" ] && print_result 0 "Video 'small' still streamable after restart" || print_result 1 "Video 'small' not streamable after restart: $response"

# Also check a chunk file exists
response=$(curl -s -o /dev/null -w "%{http_code}" ${BASE_URL}/content/small/init-0.m4s)
[ "$response" = "200" ] && print_result 0 "Video chunks accessible" || print_result 1 "Video chunks not accessible: $response"

echo

# Test 6: Get non-existent video, expect 404
echo -e "${YELLOW}Test 6: Get non-existent video, expect 404${NC}"

response=$(curl -s -o /dev/null -w "%{http_code}" ${BASE_URL}/videos/nonexistent)
[ "$response" = "404" ] && print_result 0 "Non-existent video returns 404" || print_result 1 "Non-existent video returns $response (expected 404)"

echo

# Test 7: Upload without file, expect 400
echo -e "${YELLOW}Test 7: Upload without file, expect 400${NC}"

response=$(curl -s -o /dev/null -w "%{http_code}" -X POST ${BASE_URL}/upload)
[ "$response" = "400" ] && print_result 0 "Upload without file returns 400" || print_result 1 "Upload without file returns $response (expected 400)"

echo
echo -e "${YELLOW}=== Test Summary ===${NC}"
echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}All tests passed! 🎉${NC}"
else
    echo -e "${RED}Some tests failed. Please check the implementation.${NC}"
fi

# Optional: Test with additional videos
if [ -f "small3.mp4" ] && [ -f "small4.mp4" ]; then
    echo
    echo -e "${YELLOW}=== Bonus: Testing with additional videos ===${NC}"
    
    # Upload small3.mp4
    response=$(curl -s -o /dev/null -w "%{http_code}" -L -X POST -F "file=@small3.mp4" ${BASE_URL}/upload)
    [ "$response" = "200" ] && echo -e "${GREEN}✓ small3.mp4 uploaded${NC}" || echo -e "${RED}✗ small3.mp4 upload failed${NC}"
    
    # Upload small4.mp4
    response=$(curl -s -o /dev/null -w "%{http_code}" -L -X POST -F "file=@small4.mp4" ${BASE_URL}/upload)
    [ "$response" = "200" ] && echo -e "${GREEN}✓ small4.mp4 uploaded${NC}" || echo -e "${RED}✗ small4.mp4 upload failed${NC}"
    
    # Check total video count
    video_count=$(curl -s ${BASE_URL}/ | grep -o 'href="/videos/[^"]*"' | wc -l)
    echo -e "Total videos on homepage: $video_count"
fi

# Cleanup is handled by trap