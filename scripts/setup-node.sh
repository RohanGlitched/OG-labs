#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
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

# Function to check if command exists
check_command() {
    if command -v "$1" >/dev/null 2>&1; then
        log "$1 is already installed"
        return 0
    else
        return 1
    fi
}

# Main setup function
main() {
    log "Starting 0G Storage Node setup for Node ID: ${NODE_ID:-1}"
    
    # Update system packages
    log "Updating system packages..."
    sudo apt-get update && sudo apt-get upgrade -y
    
    # Install required dependencies
    log "Installing system dependencies..."
    sudo apt install -y \
        curl iptables build-essential git wget lz4 jq make \
        protobuf-compiler cmake gcc nano automake autoconf \
        tmux htop nvme-cli libgbm1 pkg-config libssl-dev \
        libleveldb-dev tar clang bsdmainutils zstd ncdu \
        unzip libleveldb-dev screen ufw
    
    # Install Rust
    if ! check_command "rustc"; then
        log "Installing Rust..."
        curl https://sh.rustup.rs -sSf | sh -s -- -y
        source $HOME/.cargo/env
        echo 'source $HOME/.cargo/env' >> ~/.bashrc
    fi
    
    # Verify Rust installation
    source $HOME/.cargo/env
    rustc --version || { error "Rust installation failed"; exit 1; }
    
    # Install Go
    if ! check_command "go"; then
        log "Installing Go ${GO_VERSION:-1.24.3}..."
        GO_VERSION=${GO_VERSION:-"1.24.3"}
        wget -q https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz
        sudo rm -rf /usr/local/go
        sudo tar -C /usr/local -xzf go${GO_VERSION}.linux-amd64.tar.gz
        rm go${GO_VERSION}.linux-amd64.tar.gz
        
        # Add Go to PATH
        echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
        export PATH=$PATH:/usr/local/go/bin
    fi
    
    # Verify Go installation
    go version || { error "Go installation failed"; exit 1; }
    
    # Clone and build 0G Storage Node
    log "Cloning 0G Storage Node repository..."
    if [ ! -d "$HOME/0g-storage-node" ]; then
        git clone https://github.com/0glabs/0g-storage-node.git $HOME/0g-storage-node
    else
        log "Repository already exists, updating..."
        cd $HOME/0g-storage-node
        git fetch --all
    fi
    
    cd $HOME/0g-storage-node
    
    # Checkout specific version and update submodules
    log "Checking out version ${NODE_VERSION:-v1.1.0}..."
    git checkout ${NODE_VERSION:-v1.1.0}
    git submodule update --init
    
    # Build the project
    log "Building 0G Storage Node in release mode..."
    cargo build --release
    
    # Verify build
    if [ ! -f "$HOME/0g-storage-node/target/release/zgs_node" ]; then
        error "Build failed: zgs_node binary not found"
        exit 1
    fi
    
    log "Build completed successfully"
    
    # Create necessary directories
    mkdir -p $HOME/0g-storage-node/run/db
    mkdir -p $HOME/0g-storage-node/run/log
    mkdir -p $HOME/.node-state
    
    # Set up node state tracking
    cat > $HOME/.node-state/node-${NODE_ID:-1}.json << EOF
{
    "node_id": "${NODE_ID:-1}",
    "setup_time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "version": "${NODE_VERSION:-v1.1.0}",
    "status": "setup_complete"
}
EOF
    
    log "0G Storage Node setup completed successfully for Node ID: ${NODE_ID:-1}"
    log "Binary location: $HOME/0g-storage-node/target/release/zgs_node"
    log "Config directory: $HOME/0g-storage-node/run/"
}

# Error handling
trap 'error "Setup failed at line $LINENO. Exit code: $?"' ERR

# Run main function
main "$@"