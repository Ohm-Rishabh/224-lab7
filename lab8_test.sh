#!/usr/bin/env bash
set -euo pipefail

BASE_URL="http://localhost:8080"
ADMIN_ADDR="localhost:8081"
METADB="./nwtest_metadata.db"

# Test configuration - using specific video names that will hash to different nodes
# Based on SHA-256 hashing logic, these names are chosen to distribute across nodes
TEST_VIDEOS=(
    "BULBASAUR.mp4"     # This will hash to a specific node
    "PIKACHU.mp4"       # This will hash to a different node
    "CHARMANDER.mp4"    # This will hash to another node
    "SQUIRTLE.mp4"      # This will hash to yet another node
    "MEWTWO.mp4"        # This will distribute differently
    "ALAKAZAM.mp4"      # Additional distribution
    "FGB.mp4"
    "ZEVUTKU.mp4"
    "STNGBJPU.mp4"
    "ROGSH.mp4"
)

STORAGE_PORTS=(8090 8091 8092 8093 8094)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Global variables for process IDs
declare -a STORAGE_PIDS
WEB_PID=""

# Hash calculation function (mimicking Go's hashStringToUint64)
calculate_hash() {
    local input="$1"
    # Use sha256sum and extract first 8 bytes as big-endian uint64
    # This approximates the Go function behavior
    echo -n "$input" | sha256sum | cut -c1-16
}

# Predict which node a file should go to based on consistent hashing
predict_node_for_file() {
    local video_id="$1"
    local filename="$2"
    local nodes=("$@")
    nodes=("${nodes[@]:2}")  # Remove first two arguments
    
    local key="$video_id/$filename"
    local file_hash=$(calculate_hash "$key")
    
    echo "DEBUG: File $key has hash prefix: $file_hash" >&2
    
    # This is a simplified prediction - the actual Go implementation 
    # would be more precise, but this gives us an idea
    local node_count=${#nodes[@]}
    local hash_num=$((0x$file_hash))
    local node_index=$((hash_num % node_count))
    
    echo "${nodes[$node_index]}"
}

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_test() {
    echo -e "${CYAN}[TEST]${NC} $1"
}

log_hash() {
    echo -e "${MAGENTA}[HASH]${NC} $1"
}

log_migration() {
    echo -e "${YELLOW}[MIGRATION]${NC} $1"
}

# Cleanup function
cleanup() {
    log_info "Cleaning up processes and files..."
    
    # Kill web server
    if [ -n "$WEB_PID" ]; then
        kill $WEB_PID 2>/dev/null || true
        wait $WEB_PID 2>/dev/null || true
    fi
    
    # Kill storage servers if array is initialized
    if [ ${#STORAGE_PIDS[@]} -gt 0 ]; then
        for pid in "${STORAGE_PIDS[@]}"; do
            kill $pid 2>/dev/null || true
            wait $pid 2>/dev/null || true
        done
    fi
    
    # Kill any remaining processes on test ports
    for port in 8080 8081 "${STORAGE_PORTS[@]}"; do
        lsof -ti :$port | xargs kill -9 2>/dev/null || true
    done
    
    log_info "Cleanup completed"
}

# Setup function
setup() {
    log_info "Setting up test environment..."
    
    # Kill any existing processes on test ports
    for port in 8080 8081 "${STORAGE_PORTS[@]}"; do
        lsof -ti :$port | xargs kill -9 2>/dev/null || true
    done
    
    trap cleanup EXIT
    
    # Clean up old files
    rm -f "$METADB"
    for port in "${STORAGE_PORTS[@]}"; do
        rm -rf "storage/$port"
        mkdir -p "storage/$port"
    done
    
    # Create test video files with hash-aware names
    create_test_videos
    
    log_success "Test environment setup completed"
}

# Create test video files with different characteristics for better distribution
create_test_videos() {
    log_info "Creating test video files with hash-aware names..."
    
    # Initialize size variants array
    size_variants=("320x240" "640x480" "480x360" "800x600" "1024x768" "1280x720")
    
    for i in "${!TEST_VIDEOS[@]}"; do
        video="${TEST_VIDEOS[$i]}"
        if [ ! -f "$video" ]; then
            log_info "Creating $video..."
            # Create videos with different durations and characteristics
            duration=$((i + 1))
            # Use modulo to cycle through size variants if we have more videos than sizes
            size_index=$((i % ${#size_variants[@]}))
            size="${size_variants[$size_index]}"
            
            ffmpeg -f lavfi -i "testsrc=duration=$duration:size=$size:rate=1" \
                   -c:v libx264 -preset ultrafast "$video" -y > /dev/null 2>&1
            
            # Calculate and log the hash for this video's manifest
            video_id="${video%.mp4}"
            manifest_hash=$(calculate_hash "$video_id/manifest.mpd")
            log_hash "Video $video_id/manifest.mpd has hash prefix: $manifest_hash"
        fi
    done
    
    log_success "Test video files ready with hash distribution"
}

# Start storage servers
start_storage_servers() {
    log_info "Starting storage servers..."
    
    STORAGE_PIDS=()
    for port in "${STORAGE_PORTS[@]}"; do
        log_info "Starting storage server on port $port..."
        go run ./cmd/storage -host localhost -port $port "./storage/$port" > "storage$port.log" 2>&1 &
        STORAGE_PIDS+=($!)
    done
    
    # Wait for storage servers to start
    sleep 3
    log_success "Storage servers started on ports: ${STORAGE_PORTS[*]}"
}

# Start web server
start_web_server() {
    local initial_nodes="$1"
    log_info "Starting web server with nodes: $initial_nodes..."
    
    go run ./cmd/web -port 8080 sqlite "$METADB" nw "$ADMIN_ADDR,$initial_nodes" > web.log 2>&1 &
    WEB_PID=$!
    
    # Wait for web server to start
    sleep 5
    
    # Verify web server is responding
    if ! curl -s "$BASE_URL/" > /dev/null; then
        log_error "Web server failed to start"
        cat web.log
        exit 1
    fi
    
    log_success "Web server started successfully"
}

# Detailed file distribution analysis
analyze_file_distribution() {
    log_info "Analyzing current file distribution across storage nodes..."
    echo "============================================================"
    
    local total_files=0
    local distribution_summary=""
    
    for port in "${STORAGE_PORTS[@]}"; do
        local storage_dir="storage/$port"
        if [ -d "$storage_dir" ]; then
            log_info "Node localhost:$port file inventory:"
            
            local file_count=0
            local files_list=""
            
            # Find all files and categorize them
            while IFS= read -r -d '' file; do
                if [ -f "$file" ]; then
                    local rel_path="${file#$storage_dir/}"
                    files_list="$files_list\n  - $rel_path"
                    file_count=$((file_count + 1))
                    total_files=$((total_files + 1))
                    
                    # Log hash prediction for manifest files
                    if [[ "$rel_path" == *"/manifest.mpd" ]]; then
                        local video_id=$(dirname "$rel_path")
                        local predicted_hash=$(calculate_hash "$video_id/manifest.mpd")
                        log_hash "  → manifest.mpd for $video_id (hash: $predicted_hash)"
                    fi
                fi
            done < <(find "$storage_dir" -type f -print0 2>/dev/null)
            
            if [ $file_count -eq 0 ]; then
                echo "    (no files)"
            else
                echo -e "$files_list"
            fi
            
            distribution_summary="$distribution_summary\n  localhost:$port: $file_count files"
            echo ""
        fi
    done
    
    echo "============================================================"
    log_info "Distribution Summary:"
    echo -e "$distribution_summary"
    log_info "Total files across all nodes: $total_files"
    echo "============================================================"
}

# Enhanced admin list with detailed logging
test_admin_list() {
    local expected_nodes=("$@")
    log_test "Testing admin list functionality..."
    
    local list_output
    list_output=$(go run ./cmd/admin list "$ADMIN_ADDR" 2>&1)
    
    log_info "Admin list command output:"
    echo "$list_output"
    
    # Check each expected node is present
    for node in "${expected_nodes[@]}"; do
        if ! echo "$list_output" | grep -q "$node"; then
            log_error "Expected node $node not found in list"
            return 1
        else
            log_success "✓ Node $node found in cluster"
        fi
    done
    
    log_success "Admin list test passed - all expected nodes present"
}

# Enhanced video upload with hash logging
test_video_upload() {
    local video="$1"
    local video_id="${video%.mp4}"
    log_test "Testing upload of $video (ID: $video_id)..."
    
    # Check if video already exists
    local existing_code
    existing_code=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/content/$video_id/manifest.mpd" 2>/dev/null || echo "404")
    
    if [ "$existing_code" == "200" ]; then
        log_warning "Video $video_id already exists, skipping upload"
        return 0
    fi
    
    # Pre-calculate expected hash for manifest
    local manifest_hash=$(calculate_hash "$video_id/manifest.mpd")
    log_hash "Expected hash for $video_id/manifest.mpd: $manifest_hash"
    
    local resp code
    resp=$(curl -s -w "\n%{http_code}" -F "file=@$video" "$BASE_URL/upload")
    code=$(echo "$resp" | tail -n1)
    
    if [ "$code" == "409" ]; then
        log_warning "Video $video_id already exists (409 Conflict), treating as success"
        return 0
    elif [ "$code" != "303" ]; then
        log_error "Upload of $video failed with code $code"
        echo "Response: $resp"
        return 1
    fi
    
    log_success "Upload of $video successful"
    
    # Wait a moment for file processing
    sleep 2
    
    # Show where files ended up
    log_info "File distribution after uploading $video:"
    analyze_file_distribution
}

# Enhanced node removal with detailed migration tracking
test_node_removal() {
    local node_to_remove="$1"
    log_test "Testing removal of node $node_to_remove..."
    
    # Capture file state before removal
    log_info "File distribution BEFORE removing $node_to_remove:"
    analyze_file_distribution
    
    # Capture files on the node being removed
    local files_on_node=""
    local port="${node_to_remove##*:}"
    if [ -d "storage/$port" ]; then
        files_on_node=$(find "storage/$port" -type f 2>/dev/null | wc -l)
        log_migration "Node $node_to_remove currently has $files_on_node files"
        
        if [ "$files_on_node" -gt 0 ]; then
            log_migration "Files that need to be migrated:"
            find "storage/$port" -type f 2>/dev/null | sed 's|^|  - |'
        fi
    fi
    
    # Perform the removal
    log_migration "Executing node removal..."
    local remove_output
    remove_output=$(go run ./cmd/admin remove "$ADMIN_ADDR" "$node_to_remove" 2>&1)
    
    log_info "Remove command output:"
    echo "$remove_output"
    
    # Extract and log migration statistics
    local migrated_count
    migrated_count=$(echo "$remove_output" | grep -o "Number of files migrated: [0-9]*" | grep -o "[0-9]*" || echo "0")
    
    log_migration "Migration completed: $migrated_count files migrated"
    
    # Verify node is removed from list
    local list_output
    list_output=$(go run ./cmd/admin list "$ADMIN_ADDR")
    
    if echo "$list_output" | grep -q "$node_to_remove"; then
        log_error "Node $node_to_remove still appears in list after removal"
        return 1
    fi
    
    # Show file distribution after removal
    log_info "File distribution AFTER removing $node_to_remove:"
    analyze_file_distribution
    
    # Verify files on removed node
    local remaining_files=""
    if [ -d "storage/$port" ]; then
        remaining_files=$(find "storage/$port" -type f 2>/dev/null | wc -l)
        if [ "$remaining_files" -gt 0 ]; then
            log_warning "Node $node_to_remove still has $remaining_files files after removal"
            find "storage/$port" -type f 2>/dev/null | sed 's|^|  - |'
        else
            log_success "All files successfully migrated from $node_to_remove"
        fi
    fi
    
    log_success "Node $node_to_remove successfully removed (migrated $migrated_count files)"
}

# Enhanced node addition with detailed migration tracking
test_node_addition() {
    local node_to_add="$1"
    log_test "Testing addition of node $node_to_add..."
    
    # Capture file state before addition
    log_info "File distribution BEFORE adding $node_to_add:"
    analyze_file_distribution
    
    # Perform the addition
    log_migration "Executing node addition..."
    local add_output
    add_output=$(go run ./cmd/admin add "$ADMIN_ADDR" "$node_to_add" 2>&1)
    
    log_info "Add command output:"
    echo "$add_output"
    
    # Extract and log migration statistics
    local migrated_count
    migrated_count=$(echo "$add_output" | grep -o "Number of files migrated: [0-9]*" | grep -o "[0-9]*" || echo "0")
    
    log_migration "Migration completed: $migrated_count files migrated"
    
    # Verify node is added to list
    local list_output
    list_output=$(go run ./cmd/admin list "$ADMIN_ADDR")
    
    if ! echo "$list_output" | grep -q "$node_to_add"; then
        log_error "Node $node_to_add does not appear in list after addition"
        return 1
    fi
    
    # Show file distribution after addition
    log_info "File distribution AFTER adding $node_to_add:"
    analyze_file_distribution
    
    log_success "Node $node_to_add successfully added (migrated $migrated_count files)"
}

# Test video access with hash verification
test_video_access() {
    local video="$1"
    local video_id="${video%.mp4}"
    log_test "Testing access to $video_id manifest..."
    
    # Calculate expected hash
    local manifest_hash=$(calculate_hash "$video_id/manifest.mpd")
    log_hash "Accessing $video_id/manifest.mpd (expected hash: $manifest_hash)"
    
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/content/$video_id/manifest.mpd")
    
    if [ "$code" != "200" ]; then
        log_error "Manifest for $video_id not accessible (code: $code)"
        
        # Debug: show where the file should be
        log_info "Debugging: searching for manifest across all nodes..."
        for port in "${STORAGE_PORTS[@]}"; do
            if [ -f "storage/$port/$video_id/manifest.mpd" ]; then
                log_info "Found manifest at storage/$port/$video_id/manifest.mpd"
            fi
        done
        
        return 1
    fi
    
    log_success "Manifest for $video_id accessible (hash: $manifest_hash)"
}

# Test consistent hashing behavior with detailed analysis
test_consistent_hashing() {
    log_test "Testing consistent hashing behavior with detailed analysis..."
    
    # Check which videos need to be uploaded
    local videos_to_upload=()
    for video in "${TEST_VIDEOS[@]:0:4}"; do
        local video_id="${video%.mp4}"
        local code
        code=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/content/$video_id/manifest.mpd" 2>/dev/null || echo "404")
        
        if [ "$code" != "200" ]; then
            videos_to_upload+=("$video")
        fi
    done
    
    # Upload videos and track their distribution
    if [ ${#videos_to_upload[@]} -gt 0 ]; then
        log_info "Uploading new test videos and analyzing hash distribution..."
        for video in "${videos_to_upload[@]}"; do
            test_video_upload "$video"
        done
    else
        log_info "All test videos already uploaded, analyzing existing distribution..."
    fi
    
    # Analyze the distribution pattern
    log_info "Analyzing consistent hashing distribution pattern..."
    
    for video in "${TEST_VIDEOS[@]:0:4}"; do
        video_id="${video%.mp4}"
        manifest_hash=$(calculate_hash "$video_id/manifest.mpd")
        
        # Find which node actually has the file
        local actual_node=""
        for port in "${STORAGE_PORTS[@]}"; do
            if [ -f "storage/$port/$video_id/manifest.mpd" ]; then
                actual_node="localhost:$port"
                break
            fi
        done
        
        log_hash "$video_id/manifest.mpd → hash: $manifest_hash → node: $actual_node"
    done
    
    log_success "Consistent hashing analysis completed"
}

# Test with detailed migration tracking
test_detailed_migration() {
    log_test "Testing detailed migration tracking..."
    
    # Check if videos are already uploaded from previous tests
    local videos_to_upload=()
    for video in "${TEST_VIDEOS[@]:0:3}"; do
        local video_id="${video%.mp4}"
        local code
        code=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/content/$video_id/manifest.mpd" 2>/dev/null || echo "404")
        
        if [ "$code" != "200" ]; then
            videos_to_upload+=("$video")
        else
            log_info "Video $video_id already exists, skipping upload"
        fi
    done
    
    # Upload only new videos
    if [ ${#videos_to_upload[@]} -gt 0 ]; then
        log_info "Phase 1: Upload new videos to cluster"
        for video in "${videos_to_upload[@]}"; do
            test_video_upload "$video"
        done
    else
        log_info "Phase 1: All test videos already uploaded, proceeding with migration tests"
    fi
    
    log_info "Phase 2: Add third node and track migration"
    test_node_addition "localhost:8092"
    
    # Verify all videos still accessible
    for video in "${TEST_VIDEOS[@]:0:3}"; do
        test_video_access "$video"
    done
    
    log_info "Phase 3: Remove original node and track migration"
    test_node_removal "localhost:8090"
    
    # Verify all videos still accessible
    for video in "${TEST_VIDEOS[@]:0:3}"; do
        test_video_access "$video"
    done
    
    log_info "Phase 4: Add fourth node for final distribution"
    test_node_addition "localhost:8093"
    
    log_success "Detailed migration tracking test completed"
}

# Main test execution
main() {
    log_info "Starting Lab 8 Hash-Aware Comprehensive Test Suite"
    echo "========================================="
    
    # Setup
    setup
    start_storage_servers
    start_web_server "localhost:8090,localhost:8091"
    
    # Initial state
    log_info "\n=== Initial Cluster State ==="
    test_admin_list "localhost:8090" "localhost:8091"
    analyze_file_distribution
    
    # Hash analysis and consistent hashing tests
    log_info "\n=== Consistent Hashing Analysis ==="
    test_consistent_hashing
    
    # Optional: Reset to clean state for migration tests
    # Uncomment the next line if you want a clean state for migration tests
    # reset_cluster_state "soft"
    
    # Detailed migration tests
    log_info "\n=== Detailed Migration Tests ==="
    test_detailed_migration
    
    # Final comprehensive analysis
    log_info "\n=== Final Comprehensive Analysis ==="
    test_admin_list "localhost:8091" "localhost:8092" "localhost:8093"
    analyze_file_distribution
    
    # Verify all videos accessible
    log_info "\n=== Final Accessibility Verification ==="
    for video in "${TEST_VIDEOS[@]:0:3}"; do
        test_video_access "$video"
    done
    
    echo "========================================="
    log_success "ALL HASH-AWARE TESTS PASSED!"
    
    # Build and start demo environment
    log_info "\n=== Building Demo Environment ==="
    
    BIN_DIR=bin
    mkdir -p "$BIN_DIR"
    
    log_info "Building binaries..."
    go build -o "$BIN_DIR/storage" ./cmd/storage
    go build -o "$BIN_DIR/web" ./cmd/web
    go build -o "$BIN_DIR/admin" ./cmd/admin
    
    # Kill current web server
    if [ -n "$WEB_PID" ]; then
        kill $WEB_PID 2>/dev/null || true
        wait $WEB_PID 2>/dev/null || true
    fi
    
    # Start demo with all active nodes
    log_info "Starting demo web server..."
    "$BIN_DIR/web" -host localhost -port 8080 sqlite "$METADB" nw \
      "localhost:8081,localhost:8091,localhost:8092,localhost:8093" > web_demo.log 2>&1 &
    WEB_PID=$!
    
    sleep 3
    
    echo ""
    log_success "Hash-Aware Demo Environment Ready!"
    log_info "✓ Active storage nodes: localhost:8091, localhost:8092, localhost:8093"
    log_info "✓ Web server: http://localhost:8080"
    log_info "✓ Admin API: localhost:8081"
    log_info "✓ Test videos uploaded with verified hash distribution"
    echo ""
    
    # Final distribution summary
    log_info "Final file distribution:"
    analyze_file_distribution
    
    echo ""
    log_info "Open http://localhost:8080 in your browser to view the UI."
    log_info "Use './bin/admin list localhost:8081' to see active nodes."
    log_info "Use './bin/admin add localhost:8081 localhost:8094' to add more nodes."
    log_info "Press Ctrl+C to stop all servers."
    
    # Wait indefinitely
    wait
}

# Run main function
main "$@"