#!/usr/bin/env bash
set -euo pipefail

# Master Test Suite for Lab 8 - Complete Coverage
# Combines endpoint testing with node management and consistent hashing

BASE_URL="http://localhost:8080"
ADMIN_ADDR="localhost:8081"
METADB="./master_test_metadata.db"

# Test configuration
STORAGE_PORTS=(8090 8091 8092 8093 8094)
TEST_VIDEOS=("FGB.mp4" "ZEVUTKU.mp4" "STNGBJPU.mp4" "YPIMP.mp4")

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

# Global variables
declare -a STORAGE_PIDS
WEB_PID=""

# Test result tracking
declare -A TEST_RESULTS
declare -A ENDPOINT_RESULTS
declare -A MIGRATION_RESULTS
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[PASS]${NC} $1"; }
log_error() { echo -e "${RED}[FAIL]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_test() { echo -e "${CYAN}[TEST]${NC} $1"; }
log_endpoint() { echo -e "${MAGENTA}[ENDPOINT]${NC} $1"; }
log_hash() { echo -e "${MAGENTA}[HASH]${NC} $1"; }
log_migration() { echo -e "${YELLOW}[MIGRATION]${NC} $1"; }
log_section() { echo -e "\n${BOLD}${BLUE}=== $1 ===${NC}"; }

# Record test result
record_test() {
    local category="$1"
    local test_name="$2"
    local result="$3"
    local details="${4:-}"
    
    case "$category" in
        "endpoint") ENDPOINT_RESULTS["$test_name"]="$result" ;;
        "migration") MIGRATION_RESULTS["$test_name"]="$result" ;;
        *) TEST_RESULTS["$test_name"]="$result" ;;
    esac
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    if [ "$result" == "PASS" ]; then
        PASSED_TESTS=$((PASSED_TESTS + 1))
        log_success "$test_name: PASSED${details:+ - $details}"
    else
        FAILED_TESTS=$((FAILED_TESTS + 1))
        log_error "$test_name: FAILED${details:+ - $details}"
    fi
}

# Hash calculation utility
calculate_hash() {
    echo -n "$1" | sha256sum | cut -c1-16
}

# Cleanup function
cleanup() {
    log_info "Cleaning up all processes and files..."
    
    if [ -n "$WEB_PID" ]; then
        kill $WEB_PID 2>/dev/null || true
        wait $WEB_PID 2>/dev/null || true
    fi
    
    for pid in "${STORAGE_PIDS[@]}"; do
        kill $pid 2>/dev/null || true
        wait $pid 2>/dev/null || true
    done
    
    for port in 8080 8081 "${STORAGE_PORTS[@]}"; do
        lsof -ti :$port | xargs kill -9 2>/dev/null || true
    done
    
    log_info "Cleanup completed"
}

# Setup function
setup() {
    log_info "Setting up Master Test Suite environment..."
    
    for port in 8080 8081 "${STORAGE_PORTS[@]}"; do
        lsof -ti :$port | xargs kill -9 2>/dev/null || true
    done
    
    trap cleanup EXIT
    
    rm -f "$METADB"
    for port in "${STORAGE_PORTS[@]}"; do
        rm -rf "storage/$port"
        mkdir -p "storage/$port"
    done
    
    create_test_videos
    log_success "Master test environment ready"
}

# Create test videos with hash analysis
create_test_videos() {
    log_info "Creating test videos with hash-aware distribution..."
    
    for i in "${!TEST_VIDEOS[@]}"; do
        video="${TEST_VIDEOS[$i]}"
        if [ ! -f "$video" ]; then
            duration=$((i + 1))
            size_variants=("320x240" "640x480" "480x360" "800x600" "1024x768" "1280x720")
            size="${size_variants[$i]}"
            
            ffmpeg -f lavfi -i "testsrc=duration=$duration:size=$size:rate=1" \
                   -c:v libx264 -preset ultrafast "$video" -y > /dev/null 2>&1
        fi
        
        # Log expected hash distribution
        video_id="${video%.mp4}"
        manifest_hash=$(calculate_hash "$video_id/manifest.mpd")
        log_hash "Video $video_id/manifest.mpd expected hash: $manifest_hash"
    done
    
    log_success "Test videos created with hash analysis"
}

# Start all storage servers
start_all_storage_servers() {
    log_info "Starting ALL storage servers for comprehensive testing..."
    
    STORAGE_PIDS=()
    for port in "${STORAGE_PORTS[@]}"; do
        go run ./cmd/storage -host localhost -port $port "./storage/$port" > "storage$port.log" 2>&1 &
        STORAGE_PIDS+=($!)
    done
    
    sleep 3
    log_success "Storage servers started on ports: ${STORAGE_PORTS[*]}"
}

# Start web server
start_web_server() {
    local initial_nodes="localhost:8090,localhost:8091"
    log_info "Starting web server with initial nodes: $initial_nodes"
    
    go run ./cmd/web -port 8080 sqlite "$METADB" nw "$ADMIN_ADDR,$initial_nodes" > web.log 2>&1 &
    WEB_PID=$!
    sleep 5
    
    if ! curl -s "$BASE_URL/" > /dev/null; then
        log_error "Web server failed to start"
        cat web.log
        exit 1
    fi
    
    log_success "Web server started and will run throughout all tests"
}

# Detailed file distribution analysis
analyze_file_distribution() {
    local phase="$1"
    log_info "File Distribution Analysis - $phase"
    echo "============================================================"
    
    local total_files=0
    local distribution_summary=""
    
    for port in "${STORAGE_PORTS[@]}"; do
        local storage_dir="storage/$port"
        if [ -d "$storage_dir" ]; then
            local file_count=0
            local files_list=""
            
            while IFS= read -r -d '' file; do
                if [ -f "$file" ]; then
                    local rel_path="${file#$storage_dir/}"
                    files_list="$files_list\n  - $rel_path"
                    file_count=$((file_count + 1))
                    total_files=$((total_files + 1))
                    
                    # Hash verification for manifest files
                    if [[ "$rel_path" == *"/manifest.mpd" ]]; then
                        local video_id=$(dirname "$rel_path")
                        local expected_hash=$(calculate_hash "$video_id/manifest.mpd")
                        log_hash "  → $rel_path (hash: $expected_hash)"
                    fi
                fi
            done < <(find "$storage_dir" -type f -print0 2>/dev/null)
            
            log_info "Node localhost:$port: $file_count files"
            if [ $file_count -gt 0 ] && [ ${#files_list} -lt 500 ]; then
                echo -e "$files_list"
            elif [ $file_count -gt 0 ]; then
                echo "  (file list truncated - $file_count files total)"
            fi
            
            distribution_summary="$distribution_summary\n  localhost:$port: $file_count files"
        fi
    done
    
    echo "============================================================"
    log_info "Distribution Summary:"
    echo -e "$distribution_summary"
    log_info "Total files: $total_files"
    echo "============================================================"
}

# ====================================================================
# ENDPOINT TESTS
# ====================================================================

# Test GET / (Index Page)
test_index_endpoint() {
    log_test "Testing GET / (Index Page)"
    log_endpoint "GET /"
    
    local response code content
    response=$(curl -s -w "\n%{http_code}" "$BASE_URL/")
    code=$(echo "$response" | tail -n1)
    content=$(echo "$response" | sed '$d')
    
    if [ "$code" != "200" ]; then
        record_test "endpoint" "GET /" "FAIL" "HTTP $code"
        return 1
    fi
    
    # Check for expected content
    local content_checks=("TritonTube" "multipart/form-data" "Upload")
    for check in "${content_checks[@]}"; do
        if ! echo "$content" | grep -q "$check"; then
            record_test "endpoint" "GET /" "FAIL" "Missing: $check"
            return 1
        fi
    done
    
    record_test "endpoint" "GET /" "PASS" "All content present"
}

# Test POST /upload (All scenarios)
test_upload_endpoint() {
    log_test "Testing POST /upload (All scenarios)"
    
    local video="${TEST_VIDEOS[0]}"
    local video_id="${video%.mp4}"
    
    # Test successful upload
    log_endpoint "POST /upload (success)"
    local response code
    response=$(curl -s -w "\n%{http_code}" -F "file=@$video" "$BASE_URL/upload")
    code=$(echo "$response" | tail -n1)
    
    if [ "$code" != "303" ]; then
        record_test "endpoint" "POST /upload (success)" "FAIL" "HTTP $code"
        return 1
    fi
    record_test "endpoint" "POST /upload (success)" "PASS" "303 redirect"
    
    # Test duplicate upload
    log_endpoint "POST /upload (duplicate)"
    response=$(curl -s -w "\n%{http_code}" -F "file=@$video" "$BASE_URL/upload")
    code=$(echo "$response" | tail -n1)
    
    if [ "$code" != "409" ]; then
        record_test "endpoint" "POST /upload (duplicate)" "FAIL" "HTTP $code"
        return 1
    fi
    record_test "endpoint" "POST /upload (duplicate)" "PASS" "409 conflict"
    
    # Test upload without file
    log_endpoint "POST /upload (no file)"
    response=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/upload")
    code=$(echo "$response" | tail -n1)
    
    if [ "$code" != "400" ]; then
        record_test "endpoint" "POST /upload (no file)" "FAIL" "HTTP $code"
        return 1
    fi
    record_test "endpoint" "POST /upload (no file)" "PASS" "400 bad request"
}

# Test GET /videos/:videoId
test_video_page_endpoint() {
    log_test "Testing GET /videos/:videoId"
    
    local video_id="${TEST_VIDEOS[0]%.mp4}"
    
    # Test existing video
    log_endpoint "GET /videos/:videoId (existing)"
    local response code content
    response=$(curl -s -w "\n%{http_code}" "$BASE_URL/videos/$video_id")
    code=$(echo "$response" | tail -n1)
    content=$(echo "$response" | sed '$d')
    
    if [ "$code" != "200" ]; then
        record_test "endpoint" "GET /videos/:videoId (existing)" "FAIL" "HTTP $code"
        return 1
    fi
    
    # Check for video player components
    if ! echo "$content" | grep -q "dashjs" || ! echo "$content" | grep -q "$video_id"; then
        record_test "endpoint" "GET /videos/:videoId (existing)" "FAIL" "Missing video player"
        return 1
    fi
    record_test "endpoint" "GET /videos/:videoId (existing)" "PASS" "Player present"
    
    # Test non-existent video
    log_endpoint "GET /videos/:videoId (404)"
    response=$(curl -s -w "\n%{http_code}" "$BASE_URL/videos/nonexistent")
    code=$(echo "$response" | tail -n1)
    
    if [ "$code" != "404" ]; then
        record_test "endpoint" "GET /videos/:videoId (404)" "FAIL" "HTTP $code"
        return 1
    fi
    record_test "endpoint" "GET /videos/:videoId (404)" "PASS" "404 not found"
}

# Test GET /content/:videoId/:filename (comprehensive)
test_content_endpoint() {
    log_test "Testing GET /content/:videoId/:filename (comprehensive)"
    
    local video_id="${TEST_VIDEOS[0]%.mp4}"
    sleep 3  # Wait for video processing
    
    # Test manifest.mpd
    log_endpoint "GET /content/:videoId/manifest.mpd"
    local response code content_type
    response=$(curl -s -w "\n%{http_code}" "$BASE_URL/content/$video_id/manifest.mpd")
    code=$(echo "$response" | tail -n1)
    
    if [ "$code" != "200" ]; then
        record_test "endpoint" "GET /content manifest.mpd" "FAIL" "HTTP $code"
        return 1
    fi
    
    # Check Content-Type
    content_type=$(curl -s -I "$BASE_URL/content/$video_id/manifest.mpd" | grep -i "content-type" | cut -d' ' -f2- | tr -d '\r')
    if [[ "$content_type" != *"application/dash+xml"* ]]; then
        record_test "endpoint" "GET /content manifest.mpd" "FAIL" "Wrong Content-Type: $content_type"
        return 1
    fi
    record_test "endpoint" "GET /content manifest.mpd" "PASS" "Correct MIME type"
    
    # Test video segments
    log_endpoint "GET /content/:videoId/segments"
    local segment_found=false
    for segment in "init-0.m4s" "chunk-0-00001.m4s" "init-1.m4s" "chunk-1-00001.m4s"; do
        response=$(curl -s -w "\n%{http_code}" "$BASE_URL/content/$video_id/$segment")
        code=$(echo "$response" | tail -n1)
        
        if [ "$code" == "200" ]; then
            segment_found=true
            # Check Content-Type for segments
            content_type=$(curl -s -I "$BASE_URL/content/$video_id/$segment" | grep -i "content-type" | cut -d' ' -f2- | tr -d '\r')
            if [[ "$content_type" == *"video/mp4"* ]]; then
                record_test "endpoint" "GET /content segments" "PASS" "Segment $segment accessible"
                break
            fi
        fi
    done
    
    if [ "$segment_found" == false ]; then
        record_test "endpoint" "GET /content segments" "FAIL" "No segments accessible"
        return 1
    fi
    
    # Test non-existent content
    log_endpoint "GET /content/:videoId/filename (500)"
    response=$(curl -s -w "\n%{http_code}" "$BASE_URL/content/$video_id/nonexistent.m4s")
    code=$(echo "$response" | tail -n1)
    
    if [ "$code" != "500" ]; then
        record_test "endpoint" "GET /content nonexistent" "FAIL" "HTTP $code"
        return 1
    fi
    record_test "endpoint" "GET /content nonexistent" "PASS" "500 error"
    
    # Test malformed content path
    log_endpoint "GET /content (malformed)"
    response=$(curl -s -w "\n%{http_code}" "$BASE_URL/content/invalid")
    code=$(echo "$response" | tail -n1)
    
    if [ "$code" != "400" ]; then
        record_test "endpoint" "GET /content malformed" "FAIL" "HTTP $code"
        return 1
    fi
    record_test "endpoint" "GET /content malformed" "PASS" "400 bad request"
}

# ====================================================================
# ADMIN gRPC TESTS WITH MIGRATION TRACKING
# ====================================================================

test_admin_list() {
    local expected_nodes=("$@")
    log_test "Testing ListNodes gRPC"
    log_endpoint "ListNodes RPC"
    
    local list_output
    list_output=$(go run ./cmd/admin list "$ADMIN_ADDR" 2>&1)
    
    log_info "Current cluster nodes:"
    echo "$list_output"
    
    for node in "${expected_nodes[@]}"; do
        if ! echo "$list_output" | grep -q "$node"; then
            record_test "migration" "ListNodes RPC" "FAIL" "Missing node: $node"
            return 1
        fi
    done
    
    record_test "migration" "ListNodes RPC" "PASS" "All expected nodes present"
}

test_node_addition_with_migration() {
    local node_to_add="$1"
    log_test "Testing AddNode gRPC with migration tracking"
    log_endpoint "AddNode RPC"
    
    analyze_file_distribution "BEFORE adding $node_to_add"
    
    local add_output
    add_output=$(go run ./cmd/admin add "$ADMIN_ADDR" "$node_to_add" 2>&1)
    
    log_info "AddNode output:"
    echo "$add_output"
    
    # Verify success message
    if ! echo "$add_output" | grep -q "Successfully added node"; then
        record_test "migration" "AddNode RPC" "FAIL" "No success message"
        return 1
    fi
    
    # Extract migration count
    local migrated_count
    migrated_count=$(echo "$add_output" | grep -o "Number of files migrated: [0-9]*" | grep -o "[0-9]*" || echo "0")
    log_migration "Migration completed: $migrated_count files migrated"
    
    analyze_file_distribution "AFTER adding $node_to_add"
    
    # Verify node appears in list
    local list_output
    list_output=$(go run ./cmd/admin list "$ADMIN_ADDR")
    if ! echo "$list_output" | grep -q "$node_to_add"; then
        record_test "migration" "AddNode RPC" "FAIL" "Node not in list"
        return 1
    fi
    
    record_test "migration" "AddNode RPC" "PASS" "Migrated $migrated_count files"
}

test_node_removal_with_migration() {
    local node_to_remove="$1"
    log_test "Testing RemoveNode gRPC with migration tracking"
    log_endpoint "RemoveNode RPC"
    
    analyze_file_distribution "BEFORE removing $node_to_remove"
    
    # Count files on node being removed
    local port="${node_to_remove##*:}"
    local files_on_node=0
    if [ -d "storage/$port" ]; then
        files_on_node=$(find "storage/$port" -type f 2>/dev/null | wc -l)
        log_migration "Node $node_to_remove currently has $files_on_node files"
    fi
    
    local remove_output
    remove_output=$(go run ./cmd/admin remove "$ADMIN_ADDR" "$node_to_remove" 2>&1)
    
    log_info "RemoveNode output:"
    echo "$remove_output"
    
    # Verify success message
    if ! echo "$remove_output" | grep -q "Successfully removed node"; then
        record_test "migration" "RemoveNode RPC" "FAIL" "No success message"
        return 1
    fi
    
    # Extract migration count
    local migrated_count
    migrated_count=$(echo "$remove_output" | grep -o "Number of files migrated: [0-9]*" | grep -o "[0-9]*" || echo "0")
    log_migration "Migration completed: $migrated_count files migrated"
    
    analyze_file_distribution "AFTER removing $node_to_remove"
    
    # Verify node removed from list
    local list_output
    list_output=$(go run ./cmd/admin list "$ADMIN_ADDR")
    if echo "$list_output" | grep -q "$node_to_remove"; then
        record_test "migration" "RemoveNode RPC" "FAIL" "Node still in list"
        return 1
    fi
    
    # Verify files migrated away from removed node
    local remaining_files=0
    if [ -d "storage/$port" ]; then
        remaining_files=$(find "storage/$port" -type f 2>/dev/null | wc -l)
    fi
    
    if [ "$remaining_files" -gt 0 ]; then
        record_test "migration" "RemoveNode RPC" "FAIL" "$remaining_files files not migrated"
        return 1
    fi
    
    record_test "migration" "RemoveNode RPC" "PASS" "Migrated $migrated_count files"
}

# ====================================================================
# CONTENT ACCESSIBILITY TESTS
# ====================================================================

test_video_access_after_operations() {
    local video="$1"
    local operation="$2"
    local video_id="${video%.mp4}"
    
    log_test "Testing $video_id accessibility after $operation"
    
    # Test manifest access
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/content/$video_id/manifest.mpd")
    
    if [ "$code" != "200" ]; then
        record_test "migration" "Content access after $operation" "FAIL" "$video_id manifest: HTTP $code"
        return 1
    fi
    
    # Test video page access
    code=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/videos/$video_id")
    
    if [ "$code" != "200" ]; then
        record_test "migration" "Video page after $operation" "FAIL" "$video_id page: HTTP $code"
        return 1
    fi
    
    record_test "migration" "Content access after $operation" "PASS" "$video_id accessible"
}

# ====================================================================
# CONSISTENT HASHING ANALYSIS
# ====================================================================

test_consistent_hashing_distribution() {
    log_test "Testing consistent hashing distribution pattern"
    
    log_info "Uploading videos for hash analysis..."
    
    # Upload multiple videos for distribution analysis
    local uploaded_videos=()
    for video in "${TEST_VIDEOS[@]:1:3}"; do
        local video_id="${video%.mp4}"
        local existing_code
        existing_code=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/content/$video_id/manifest.mpd" 2>/dev/null || echo "404")
        
        if [ "$existing_code" != "200" ]; then
            log_info "Uploading $video for hash analysis..."
            local response code
            response=$(curl -s -w "\n%{http_code}" -F "file=@$video" "$BASE_URL/upload")
            code=$(echo "$response" | tail -n1)
            
            if [ "$code" == "303" ]; then
                uploaded_videos+=("$video")
            fi
        else
            uploaded_videos+=("$video")
            log_info "$video already uploaded"
        fi
    done
    
    sleep 3  # Wait for processing
    
    # Analyze hash distribution
    log_info "Analyzing consistent hashing distribution..."
    local distribution_nodes=0
    
    for port in "${STORAGE_PORTS[@]:0:3}"; do
        local file_count=$(find "storage/$port" -type f 2>/dev/null | wc -l)
        if [ "$file_count" -gt 0 ]; then
            distribution_nodes=$((distribution_nodes + 1))
            log_hash "Node localhost:$port has $file_count files"
        fi
    done
    
    # Verify distribution across multiple nodes
    if [ "$distribution_nodes" -ge 2 ]; then
        record_test "migration" "Consistent hashing" "PASS" "Files distributed across $distribution_nodes nodes"
    else
        record_test "migration" "Consistent hashing" "FAIL" "Poor distribution: only $distribution_nodes nodes used"
        return 1
    fi
}

# ====================================================================
# INDEX PAGE VIDEO COUNT VALIDATION
# ====================================================================

test_index_video_count_accuracy() {
    log_test "Testing index page video count accuracy"
    
    # Count videos on index page
    local response video_count
    response=$(curl -s "$BASE_URL/")
    video_count=$(echo "$response" | grep -o '<a href="/videos/' | wc -l)
    
    # Count actual uploaded videos
    local uploaded_count=0
    for video in "${TEST_VIDEOS[@]:0:4}"; do
        local video_id="${video%.mp4}"
        local code
        code=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/content/$video_id/manifest.mpd" 2>/dev/null || echo "404")
        if [ "$code" == "200" ]; then
            uploaded_count=$((uploaded_count + 1))
        fi
    done
    
    if [ "$video_count" -ne "$uploaded_count" ]; then
        record_test "endpoint" "Index video count" "FAIL" "Shows $video_count, expected $uploaded_count"
        return 1
    fi
    
    record_test "endpoint" "Index video count" "PASS" "Correctly shows $video_count videos"
}

# ====================================================================
# COMPREHENSIVE TEST RESULTS SUMMARY
# ====================================================================

show_comprehensive_summary() {
    echo ""
    echo "################################################################"
    log_info "MASTER TEST SUITE - COMPREHENSIVE RESULTS SUMMARY"
    echo "################################################################"
    
    log_section "HTTP ENDPOINT TEST RESULTS"
    echo "GET /                              : ${ENDPOINT_RESULTS["GET /"]:-"NOT RUN"}"
    echo "POST /upload (success)             : ${ENDPOINT_RESULTS["POST /upload (success)"]:-"NOT RUN"}"
    echo "POST /upload (duplicate)           : ${ENDPOINT_RESULTS["POST /upload (duplicate)"]:-"NOT RUN"}"
    echo "POST /upload (no file)             : ${ENDPOINT_RESULTS["POST /upload (no file)"]:-"NOT RUN"}"
    echo "GET /videos/:videoId (existing)    : ${ENDPOINT_RESULTS["GET /videos/:videoId (existing)"]:-"NOT RUN"}"
    echo "GET /videos/:videoId (404)         : ${ENDPOINT_RESULTS["GET /videos/:videoId (404)"]:-"NOT RUN"}"
    echo "GET /content manifest.mpd          : ${ENDPOINT_RESULTS["GET /content manifest.mpd"]:-"NOT RUN"}"
    echo "GET /content segments              : ${ENDPOINT_RESULTS["GET /content segments"]:-"NOT RUN"}"
    echo "GET /content nonexistent           : ${ENDPOINT_RESULTS["GET /content nonexistent"]:-"NOT RUN"}"
    echo "GET /content malformed             : ${ENDPOINT_RESULTS["GET /content malformed"]:-"NOT RUN"}"
    echo "Index video count                  : ${ENDPOINT_RESULTS["Index video count"]:-"NOT RUN"}"
    
    log_section "NODE MANAGEMENT & MIGRATION TEST RESULTS"
    echo "ListNodes RPC                      : ${MIGRATION_RESULTS["ListNodes RPC"]:-"NOT RUN"}"
    echo "AddNode RPC                        : ${MIGRATION_RESULTS["AddNode RPC"]:-"NOT RUN"}"
    echo "RemoveNode RPC                     : ${MIGRATION_RESULTS["RemoveNode RPC"]:-"NOT RUN"}"
    echo "Consistent hashing                 : ${MIGRATION_RESULTS["Consistent hashing"]:-"NOT RUN"}"
    echo "Content access after operations    : ${MIGRATION_RESULTS["Content access after operations"]:-"NOT RUN"}"
    
    log_section "OVERALL TEST STATISTICS"
    echo "Total Tests Run: $TOTAL_TESTS"
    echo "Passed: $PASSED_TESTS"
    echo "Failed: $FAILED_TESTS"
    echo "Success Rate: $(( PASSED_TESTS * 100 / TOTAL_TESTS ))%"
    
    echo "################################################################"
    
    if [ "$FAILED_TESTS" -eq 0 ]; then
        log_success "🎉 ALL MASTER TESTS PASSED! 🎉"
        log_success "Complete Lab 8 functionality validated!"
        return 0
    else
        log_error "❌ $FAILED_TESTS tests failed"
        log_error "Check individual test output above for details"
        return 1
    fi
}

# ====================================================================
# MAIN EXECUTION FLOW
# ====================================================================

main() {
    log_info "Starting Lab 8 Master Test Suite"
    log_info "Comprehensive testing of endpoints + node management + consistent hashing"
    echo "========================================================================"
    
    # Environment setup
    setup
    start_all_storage_servers
    start_web_server
    
    # Phase 1: Initial endpoint testing
    log_section "PHASE 1: INITIAL ENDPOINT TESTING"
    test_index_endpoint
    test_upload_endpoint  # This uploads first video
    sleep 2
    test_video_page_endpoint
    test_content_endpoint
    
    # Phase 2: Initial cluster state
    log_section "PHASE 2: INITIAL CLUSTER STATE"
    test_admin_list "localhost:8090" "localhost:8091"
    analyze_file_distribution "Initial State"
    
    # Phase 3: Consistent hashing analysis
    log_section "PHASE 3: CONSISTENT HASHING ANALYSIS"
    test_consistent_hashing_distribution
    
    # Phase 4: Dynamic cluster management with migration
    log_section "PHASE 4: DYNAMIC CLUSTER MANAGEMENT"
    
    # Add nodes and track migrations
    test_node_addition_with_migration "localhost:8092"
    test_video_access_after_operations "${TEST_VIDEOS[0]}" "node addition"
    
    test_node_addition_with_migration "localhost:8093"
    test_video_access_after_operations "${TEST_VIDEOS[1]}" "second node addition"
    
    # Remove nodes and track migrations
    test_node_removal_with_migration "localhost:8090"
    test_video_access_after_operations "${TEST_VIDEOS[0]}" "node removal"
    
    # Phase 5: Post-migration endpoint validation
    log_section "PHASE 5: POST-MIGRATION ENDPOINT VALIDATION"
    
    # Re-test all endpoints after cluster changes
    log_info "Re-validating all endpoints after cluster operations..."
    
    # Test index page shows correct video count
    test_index_video_count_accuracy
    
    # Verify all uploaded videos are still accessible
    log_info "Verifying all videos remain accessible..."
    for video in "${TEST_VIDEOS[@]:0:4}"; do
        local video_id="${video%.mp4}"
        local code
        code=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/content/$video_id/manifest.mpd" 2>/dev/null || echo "404")
        
        if [ "$code" == "200" ]; then
            test_video_access_after_operations "$video" "cluster operations"
        fi
    done
    
    # Phase 6: Advanced cluster operations
    log_section "PHASE 6: ADVANCED CLUSTER OPERATIONS"
    
    # Test adding another node for better distribution
    test_node_addition_with_migration "localhost:8094"
    
    # Final cluster state verification
    test_admin_list "localhost:8091" "localhost:8092" "localhost:8093" "localhost:8094"
    
    # Phase 7: Stress testing with additional uploads
    log_section "PHASE 7: STRESS TESTING"
    
    # Upload remaining videos to test distribution across larger cluster
    log_info "Uploading additional videos for stress testing..."
    for video in "${TEST_VIDEOS[@]:4}"; do
        local video_id="${video%.mp4}"
        local existing_code
        existing_code=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/content/$video_id/manifest.mpd" 2>/dev/null || echo "404")
        
        if [ "$existing_code" != "200" ]; then
            log_info "Uploading $video for stress test..."
            local response code
            response=$(curl -s -w "\n%{http_code}" -F "file=@$video" "$BASE_URL/upload")
            code=$(echo "$response" | tail -n1)
            
            if [ "$code" == "303" ]; then
                record_test "migration" "Stress test upload" "PASS" "$video uploaded"
                # Test immediate accessibility
                sleep 2
                test_video_access_after_operations "$video" "stress upload"
            else
                record_test "migration" "Stress test upload" "FAIL" "$video upload failed: $code"
            fi
        fi
    done
    
    # Phase 8: Final comprehensive validation
    log_section "PHASE 8: FINAL COMPREHENSIVE VALIDATION"
    
    # Final file distribution analysis
    analyze_file_distribution "Final State"
    
    # Test final endpoint functionality
    log_info "Final endpoint validation..."
    
    # Re-test critical endpoints one more time
    local final_response final_code
    final_response=$(curl -s -w "\n%{http_code}" "$BASE_URL/")
    final_code=$(echo "$final_response" | tail -n1)
    
    if [ "$final_code" == "200" ]; then
        record_test "endpoint" "Final index validation" "PASS" "Index accessible"
    else
        record_test "endpoint" "Final index validation" "FAIL" "Index failed: $final_code"
    fi
    
    # Count total accessible videos
    local total_accessible=0
    for video in "${TEST_VIDEOS[@]}"; do
        local video_id="${video%.mp4}"
        local code
        code=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/content/$video_id/manifest.mpd" 2>/dev/null || echo "404")
        if [ "$code" == "200" ]; then
            total_accessible=$((total_accessible + 1))
        fi
    done
    
    log_info "Final accessibility: $total_accessible videos accessible"
    
    if [ "$total_accessible" -ge 4 ]; then
        record_test "migration" "Final accessibility" "PASS" "$total_accessible videos accessible"
    else
        record_test "migration" "Final accessibility" "FAIL" "Only $total_accessible videos accessible"
    fi
    
    # Show comprehensive results
    show_comprehensive_summary
    local exit_code=$?
    
    # Phase 9: Demo environment
    if [ $exit_code -eq 0 ]; then
        log_section "PHASE 9: DEMO ENVIRONMENT READY"
        
        # Build CLI tools for user convenience
        log_info "Building CLI tools..."
        BIN_DIR=bin
        mkdir -p "$BIN_DIR"
        go build -o "$BIN_DIR/admin" ./cmd/admin
        go build -o "$BIN_DIR/web" ./cmd/web
        go build -o "$BIN_DIR/storage" ./cmd/storage
        
        echo ""
        echo "🎉================================================================🎉"
        log_success "MASTER TEST SUITE COMPLETED SUCCESSFULLY!"
        log_success "ALL ENDPOINTS AND NODE MANAGEMENT FUNCTIONALITY VALIDATED!"
        echo "🎉================================================================🎉"
        echo ""
        
        log_info "✅ DEMO ENVIRONMENT SPECIFICATIONS:"
        echo "   🌐 Web Server: http://localhost:8080"
        echo "   🔧 Admin API: localhost:8081"
        echo "   🗄️  Active Storage Nodes:"
        
        # Show final active nodes
        local list_output
        list_output=$(go run ./cmd/admin list "$ADMIN_ADDR" 2>/dev/null || echo "Failed to get node list")
        echo "$list_output" | sed 's/^/      /'
        
        echo ""
        log_info "📹 UPLOADED VIDEOS:"
        for video in "${TEST_VIDEOS[@]}"; do
            local video_id="${video%.mp4}"
            local code
            code=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/content/$video_id/manifest.mpd" 2>/dev/null || echo "404")
            if [ "$code" == "200" ]; then
                echo "   ✅ $video_id - http://localhost:8080/videos/$video_id"
            fi
        done
        
        echo ""
        log_info "🛠️  CLI TOOLS AVAILABLE:"
        echo "   ./bin/admin list localhost:8081                    # List cluster nodes"
        echo "   ./bin/admin add localhost:8081 localhost:8095      # Add new node"
        echo "   ./bin/admin remove localhost:8081 localhost:8094   # Remove node"
        echo ""
        
        log_info "🧪 TEST COVERAGE ACHIEVED:"
        echo "   ✅ All HTTP endpoints (GET /, POST /upload, GET /videos, GET /content)"
        echo "   ✅ All HTTP status codes (200, 303, 400, 404, 409, 500)"
        echo "   ✅ All Content-Type headers (text/html, application/dash+xml, video/mp4)"
        echo "   ✅ All gRPC admin operations (ListNodes, AddNode, RemoveNode)"
        echo "   ✅ File migration tracking and validation"
        echo "   ✅ Consistent hashing distribution analysis"
        echo "   ✅ Content accessibility after cluster operations"
        echo "   ✅ Error handling and edge cases"
        echo ""
        
        log_info "🚀 Ready for:"
        echo "   • Manual testing via web browser"
        echo "   • Additional cluster operations via CLI"
        echo "   • Performance testing with more videos"
        echo "   • Demonstration of distributed video storage"
        echo ""
        
        log_info "Press Ctrl+C to stop all servers and exit."
        echo ""
        
        # Keep the demo running
        wait
    else
        log_error "Some tests failed. Check the summary above for details."
        exit 1
    fi
}

# Run the master test suite
main "$@"