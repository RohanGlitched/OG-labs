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
NODE_DIR="$HOME/0g-storage-node"
STATE_DIR="$HOME/.node-state"
LOG_DIR="$NODE_DIR/run/log"
DB_DIR="$NODE_DIR/run/db"

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Function to get final node status
get_final_status() {
    local response
    response=$(curl -s -X POST http://localhost:5678 \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"zgs_getStatus","params":[],"id":1}' \
        --max-time 10 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$response" ]; then
        echo "$response"
    else
        echo '{"error": "connection_failed"}'
    fi
}

# Function to collect system statistics
collect_system_stats() {
    local stats_file="$STATE_DIR/system-stats-${NODE_ID}.json"
    
    cat > "$stats_file" << EOF
{
    "node_id": "$NODE_ID",
    "cleanup_time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "system_stats": {
        "cpu_usage": "$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | awk -F'%' '{print $1}')",
        "memory_usage": "$(free -m | awk 'NR==2{printf "%.1f%%", $3*100/$2 }')",
        "disk_usage": "$(df -h $HOME | awk 'NR==2 {print $5}')",
        "load_average": "$(uptime | awk -F'load average:' '{print $2}' | xargs)"
    }
}
EOF
    
    log "System statistics collected in $stats_file"
}

# Function to compress and organize logs
organize_logs() {
    local log_archive="$STATE_DIR/logs-node-${NODE_ID}-$(date +%Y%m%d-%H%M%S).tar.gz"
    
    if [ -d "$LOG_DIR" ]; then
        log "Compressing logs for Node $NODE_ID..."
        
        # Create logs directory in state if it doesn't exist
        mkdir -p "$STATE_DIR/logs"
        
        # Archive all log files
        cd "$LOG_DIR"
        if ls *.log* 1> /dev/null 2>&1; then
            tar -czf "$log_archive" *.log* 2>/dev/null || {
                warn "Failed to compress some log files"
            }
            log "Logs archived to $log_archive"
        else
            warn "No log files found to archive"
        fi
        
        # Keep only the latest 3 log files to save space
        ls -t *.log* 2>/dev/null | tail -n +4 | xargs rm -f 2>/dev/null || true
    else
        warn "Log directory not found: $LOG_DIR"
    fi
}

# Function to save database state
save_db_state() {
    if [ -d "$DB_DIR" ]; then
        local db_size=$(du -sh "$DB_DIR" 2>/dev/null | cut -f1)
        log "Database directory size: $db_size"
        
        # Create database state summary
        cat > "$STATE_DIR/db-state-${NODE_ID}.json" << EOF
{
    "node_id": "$NODE_ID",
    "db_path": "$DB_DIR",
    "db_size": "$db_size",
    "last_modified": "$(stat -c %y "$DB_DIR" 2>/dev/null || echo 'unknown')",
    "file_count": $(find "$DB_DIR" -type f 2>/dev/null | wc -l),
    "cleanup_time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
        
        # Verify critical database files exist
        if [ -d "$DB_DIR/flow_db" ]; then
            log "Flow database preserved for next run"
        else
            warn "Flow database not found - next run will need to download snapshot"
        fi
    else
        warn "Database directory not found: $DB_DIR"
    fi
}

# Function to cleanup temporary files and processes
cleanup_processes() {
    log "Cleaning up processes and temporary files for Node $NODE_ID..."
    
    # Kill any remaining node processes
    pkill -f "zgs_node.*config.*node.*${NODE_ID}" 2>/dev/null || true
    
    # Clean up any lock files
    find "$NODE_DIR/run" -name "*.lock" -delete 2>/dev/null || true
    
    # Clean up temporary files
    find "/tmp" -name "*zgs*" -user $(whoami) -delete 2>/dev/null || true
    
    # Clean up old state files (keep last 5)
    if [ -d "$STATE_DIR" ]; then
        find "$STATE_DIR" -name "node-${NODE_ID}-*.json" -type f | \
        head -n -5 | xargs rm -f 2>/dev/null || true
    fi
    
    log "Process cleanup completed"
}

# Function to create restart preparation file
prepare_restart() {
    local restart_file="$STATE_DIR/restart-${NODE_ID}.json"
    local final_status=$(get_final_status)
    local sync_height="unknown"
    local peers="unknown"
    
    if [ "$final_status" != '{"error": "connection_failed"}' ]; then
        sync_height=$(echo "$final_status" | jq -r '.result.logSyncHeight // "unknown"')
        peers=$(echo "$final_status" | jq -r '.result.connectedPeers // "unknown"')
    fi
    
    cat > "$restart_file" << EOF
{
    "node_id": "$NODE_ID",
    "last_run_end": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "last_sync_height": "$sync_height",
    "last_peer_count": "$peers",
    "database_preserved": $([ -d "$DB_DIR/flow_db" ] && echo "true" || echo "false"),
    "ready_for_restart": true,
    "restart_notes": {
        "snapshot_needed": $([ ! -d "$DB_DIR/flow_db" ] && echo "true" || echo "false"),
        "config_location": "$NODE_DIR/run/config.toml",
        "estimated_sync_time": "$([ -d "$DB_DIR/flow_db" ] && echo '5-10 minutes' || echo '30-60 minutes')"
    }
}
EOF
    
    log "Restart preparation file created: $restart_file"
}

# Function to generate cleanup summary
generate_summary() {
    local summary_file="$STATE_DIR/cleanup-summary-${NODE_ID}.json"
    
    cat > "$summary_file" << EOF
{
    "node_id": "$NODE_ID",
    "cleanup_completed": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "actions_performed": [
        "System statistics collected",
        "Logs organized and compressed",
        "Database state saved",
        "Processes cleaned up",
        "Restart preparation completed"
    ],
    "files_created": [
        "system-stats-${NODE_ID}.json",
        "db-state-${NODE_ID}.json", 
        "restart-${NODE_ID}.json",
        "cleanup-summary-${NODE_ID}.json"
    ],
    "next_run_ready": true
}
EOF
    
    log "Cleanup summary created: $summary_file"
}

# Main cleanup function
main() {
    log "Starting cleanup for 0G Storage Node $NODE_ID..."
    
    # Create state directory if it doesn't exist
    mkdir -p "$STATE_DIR"
    
    # Collect final statistics
    collect_system_stats
    
    # Organize and compress logs
    organize_logs
    
    # Save database state information
    save_db_state
    
    # Clean up processes and temporary files
    cleanup_processes
    
    # Prepare for restart
    prepare_restart
    
    # Generate cleanup summary
    generate_summary
    
    log "Cleanup completed successfully for Node $NODE_ID"
    log "State directory: $STATE_DIR"
    log "Database preserved: $([ -d "$DB_DIR/flow_db" ] && echo 'Yes' || echo 'No')"
    log "Ready for next run: Yes"
}

# Error handling
trap 'error "Cleanup failed at line $LINENO"' ERR

# Run main function
main "$@"