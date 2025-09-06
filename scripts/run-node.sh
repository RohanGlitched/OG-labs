#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NODE_ID=${NODE_ID:-1}
LOG_FILE=${LOG_FILE:-"node-${NODE_ID}-$(date +%Y%m%d-%H%M%S).log"}
MONITOR_INTERVAL=30  # seconds
HEALTH_CHECK_INTERVAL=300  # 5 minutes
MAX_RUNTIME=21000  # ~5h 50min in seconds (350 minutes)
NODE_DIR="$HOME/0g-storage-node"
CONFIG_FILE="$HOME/0g-storage-node/run/config.toml"
STATE_DIR="$HOME/.node-state"

# PID tracking
NODE_PID=""
MONITOR_PID=""

# Logging functions
log() {
    local msg="[$(date +'%Y-%m-%d %H:%M:%S')] $1"
    echo -e "${GREEN}${msg}${NC}"
    echo "$msg" >> "$LOG_FILE"
}

error() {
    local msg="[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1"
    echo -e "${RED}${msg}${NC}"
    echo "$msg" >> "$LOG_FILE"
}

warn() {
    local msg="[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1"
    echo -e "${YELLOW}${msg}${NC}"
    echo "$msg" >> "$LOG_FILE"
}

info() {
    local msg="[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1"
    echo -e "${BLUE}${msg}${NC}"
    echo "$msg" >> "$LOG_FILE"
}

# Function to get node status via RPC
get_node_status() {
    local node_port=$((5678 + ${NODE_ID}))
    local response
    response=$(curl -s -X POST http://localhost:${node_port} \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"zgs_getStatus","params":[],"id":1}' \
        --max-time 10 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$response" ]; then
        echo "$response"
    else
        echo '{"error": "connection_failed"}'
    fi
}

# Function to extract values from JSON response
extract_json_value() {
    local json="$1"
    local key="$2"
    echo "$json" | jq -r ".result.${key} // \"unknown\""
}

# Monitor node health and sync status
monitor_node() {
    local start_time=$(date +%s)
    local stats_file="$STATE_DIR/stats.json"
    
    log "Starting node monitoring for Node $NODE_ID"
    
    while true; do
        sleep $MONITOR_INTERVAL
        
        # Check if main process is still running
        if ! kill -0 $NODE_PID 2>/dev/null; then
            error "Node process has stopped unexpectedly"
            break
        fi
        
        # Get current runtime
        local current_time=$(date +%s)
        local runtime=$((current_time - start_time))
        local runtime_minutes=$((runtime / 60))
        
        # Check if we've reached max runtime
        if [ $runtime -ge $MAX_RUNTIME ]; then
            log "Maximum runtime reached (${runtime_minutes} minutes). Initiating graceful shutdown..."
            break
        fi
        
        # Health check every 5 minutes
        if [ $((runtime % HEALTH_CHECK_INTERVAL)) -eq 0 ] || [ $runtime -lt $HEALTH_CHECK_INTERVAL ]; then
            local status_response=$(get_node_status)
            local sync_height=$(extract_json_value "$status_response" "logSyncHeight")
            local connected_peers=$(extract_json_value "$status_response" "connectedPeers")
            
            if [ "$sync_height" != "unknown" ] && [ "$connected_peers" != "unknown" ]; then
                log "Node $NODE_ID Status - Sync Height: $sync_height, Peers: $connected_peers, Runtime: ${runtime_minutes}m"
                
                # Update stats file
                cat > "$stats_file" << EOF
{
    "node_id": "$NODE_ID",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "sync_height": $sync_height,
    "connected_peers": $connected_peers,
    "uptime_minutes": $runtime_minutes,
    "status": "running",
    "pid": $NODE_PID
}
EOF
            else
                warn "Failed to get node status - Node might be starting up or having connection issues"
                
                # Update stats with error state
                cat > "$stats_file" << EOF
{
    "node_id": "$NODE_ID",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "sync_height": "unknown",
    "connected_peers": "unknown",
    "uptime_minutes": $runtime_minutes,
    "status": "error",
    "pid": $NODE_PID,
    "error": "rpc_connection_failed"
}
EOF
            fi
        fi
        
        # Log progress every 10 minutes
        if [ $((runtime % 600)) -eq 0 ] && [ $runtime -gt 0 ]; then
            log "Node $NODE_ID has been running for ${runtime_minutes} minutes (${MAX_RUNTIME} max)"
        fi
    done
    
    log "Monitor loop ended for Node $NODE_ID"
}

# Graceful shutdown function
graceful_shutdown() {
    log "Initiating graceful shutdown for Node $NODE_ID..."
    
    # Stop monitor if running
    if [ -n "$MONITOR_PID" ] && kill -0 $MONITOR_PID 2>/dev/null; then
        kill $MONITOR_PID 2>/dev/null || true
        wait $MONITOR_PID 2>/dev/null || true
        log "Monitor process stopped"
    fi
    
    # Stop main node process
    if [ -n "$NODE_PID" ] && kill -0 $NODE_PID 2>/dev/null; then
        log "Stopping node process (PID: $NODE_PID)..."
        kill -TERM $NODE_PID 2>/dev/null || true
        
        # Wait up to 30 seconds for graceful shutdown
        local count=0
        while [ $count -lt 30 ] && kill -0 $NODE_PID 2>/dev/null; do
            sleep 1
            count=$((count + 1))
        done
        
        # Force kill if still running
        if kill -0 $NODE_PID 2>/dev/null; then
            warn "Node didn't stop gracefully, force killing..."
            kill -KILL $NODE_PID 2>/dev/null || true
        fi
        
        log "Node process stopped"
    fi
    
    # Update final stats
    local final_response=$(get_node_status)
    local final_sync_height=$(extract_json_value "$final_response" "logSyncHeight")
    local final_peers=$(extract_json_value "$final_response" "connectedPeers")
    local end_time=$(date +%s)
    local total_runtime=$(( (end_time - $(date -d "$(cat $STATE_DIR/node-${NODE_ID}.json | jq -r .setup_time)" +%s)) / 60 ))
    
    cat > "$STATE_DIR/stats.json" << EOF
{
    "node_id": "$NODE_ID",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "final_sync_height": "${final_sync_height:-unknown}",
    "connected_peers": "${final_peers:-unknown}",
    "uptime_minutes": $total_runtime,
    "status": "stopped",
    "shutdown_reason": "graceful"
}
EOF
    
    log "Graceful shutdown completed for Node $NODE_ID"
}

# Signal handlers
trap graceful_shutdown EXIT INT TERM

# Main execution
main() {
    log "Starting 0G Storage Node $NODE_ID"
    
    # Verify prerequisites
    if [ ! -f "$CONFIG_FILE" ]; then
        error "Config file not found: $CONFIG_FILE"
        exit 1
    fi
    
    if [ ! -f "$NODE_DIR/target/release/zgs_node" ]; then
        error "Node binary not found: $NODE_DIR/target/release/zgs_node"
        exit 1
    fi
    
    # Create state directory if it doesn't exist
    mkdir -p "$STATE_DIR"
    
    # Verify binary exists and is executable
    if [ ! -f "$NODE_DIR/target/release/zgs_node" ]; then
        error "Node binary not found at $NODE_DIR/target/release/zgs_node"
        exit 1
    fi
    
    if [ ! -x "$NODE_DIR/target/release/zgs_node" ]; then
        log "Making node binary executable..."
        chmod +x "$NODE_DIR/target/release/zgs_node"
    fi
    
    # Test binary execution
    log "Testing binary execution..."
    if "$NODE_DIR/target/release/zgs_node" --help >/dev/null 2>&1; then
        log "Binary test successful"
    else
        error "Binary test failed - checking dependencies..."
        ldd "$NODE_DIR/target/release/zgs_node" 2>&1 | head -10 | while read line; do
            error "  $line"
        done
        exit 1
    fi
    
    # Verify config file
    log "Checking configuration file: $CONFIG_FILE"
    if [ ! -f "$CONFIG_FILE" ]; then
        error "Config file not found: $CONFIG_FILE"
        exit 1
    fi
    
    # Show config content for debugging
    log "Configuration preview:"
    head -20 "$CONFIG_FILE" | while read line; do
        log "  $line"
    done
    
    # Create log directory if it doesn't exist
    mkdir -p "$NODE_DIR/run/log"
    
    # Start the node
    log "Starting 0G Storage Node binary..."
    cd "$NODE_DIR/run"
    
    # Try to start node and capture any immediate errors
    log "Executing: $NODE_DIR/target/release/zgs_node --config $CONFIG_FILE"
    
    # Start node in background with detailed logging
    "$NODE_DIR/target/release/zgs_node" --config "$CONFIG_FILE" > "$LOG_FILE" 2>&1 &
    NODE_PID=$!
    
    log "Node started with PID: $NODE_PID"
    
    # Wait a bit and check multiple times
    for i in {1..5}; do
        sleep 2
        if kill -0 $NODE_PID 2>/dev/null; then
            log "Node is running (check $i/5)"
        else
            error "Node process crashed after $((i*2)) seconds"
            
            # Show the last few lines of the log file for debugging
            if [ -f "$LOG_FILE" ]; then
                error "Last 20 lines of node log:"
                tail -20 "$LOG_FILE" | while read line; do
                    error "  $line"
                done
            fi
            
            # Also check system logs
            error "System log entries for zgs_node:"
            journalctl --no-pager -u zgs 2>/dev/null | tail -10 | while read line; do
                error "  $line"
            done || error "No system logs available"
            
            exit 1
        fi
    done
    
    log "Node successfully started and running"
    
    # Start monitoring in background
    monitor_node &
    MONITOR_PID=$!
    
    log "Monitor started with PID: $MONITOR_PID"
    
    # Update node state
    cat > "$STATE_DIR/node-${NODE_ID}.json" << EOF
{
    "node_id": "$NODE_ID",
    "start_time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "pid": $NODE_PID,
    "monitor_pid": $MONITOR_PID,
    "status": "running"
}
EOF
    
    # Wait for the node to complete or be terminated
    wait $NODE_PID
    local node_exit_code=$?
    
    log "Node process exited with code: $node_exit_code"
    
    # Stop monitor
    if [ -n "$MONITOR_PID" ] && kill -0 $MONITOR_PID 2>/dev/null; then
        kill $MONITOR_PID 2>/dev/null || true
        wait $MONITOR_PID 2>/dev/null || true
    fi
    
    log "Node $NODE_ID execution completed"
    return $node_exit_code
}

# Check if running directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi