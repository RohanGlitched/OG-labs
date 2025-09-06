# 0G Storage Nodes - GitHub Actions Parallel Deployment

This repository contains a complete GitHub Actions setup for running multiple 0G Storage Nodes in parallel, with automatic 6-hour cycles and state persistence for continuous operation.

## 📋 Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Setup Instructions](#setup-instructions)
- [Configuration](#configuration)
- [Running the Nodes](#running-the-nodes)
- [Monitoring](#monitoring)
- [Troubleshooting](#troubleshooting)
- [File Structure](#file-structure)

## 🎯 Overview

### Features

- **Parallel Execution**: Run multiple storage nodes simultaneously (default: 5 nodes)
- **6-Hour Cycles**: Automatic restart every 6 hours for continuous operation
- **State Persistence**: Seamless resume from previous sync point using GitHub Actions cache
- **Auto-Restart**: Scheduled re-execution using GitHub cron jobs
- **Health Monitoring**: Real-time sync status and peer connection tracking
- **Resource Optimization**: Efficient use of GitHub Actions limits and storage

### Architecture

```
GitHub Actions Workflow
├── Matrix Strategy (Parallel Jobs)
│   ├── Node 1 (Instance 1)
│   ├── Node 2 (Instance 2)
│   ├── Node 3 (Instance 3)
│   ├── Node 4 (Instance 4)
│   └── Node 5 (Instance 5)
├── State Management (Cache & Artifacts)
├── Health Monitoring
└── Automatic Restart (Cron Schedule)
```

## 🛠 Prerequisites

### GitHub Repository Setup

1. **Fork this repository** or create a new one with these files
2. **Enable GitHub Actions** in your repository settings
3. **Set up required secrets** (see Configuration section)

### Required Secrets

Set the following secrets in your GitHub repository (`Settings > Secrets and variables > Actions`):

#### Option 1: Single Credentials (Recommended - Simpler Setup)

| Secret Name | Description | Example Value |
|-------------|-------------|---------------|
| `MINER_PRIVATE_KEY` | Your wallet's private key (without 0x) | `abcdef123456789...` |
| `RPC_ENDPOINT` | RPC endpoint URL | `https://evmrpc-testnet.0g.ai` |

#### Option 2: Individual Credentials Per Node (Advanced)

| Secret Name | Description | Example Format |
|-------------|-------------|----------------|
| `MINER_PRIVATE_KEYS` | Array of private keys for each node | `["key1", "key2", "key3", "key4", "key5"]` |
| `RPC_ENDPOINTS` | Array of RPC endpoints | `["https://evmrpc-testnet.0g.ai", "https://rpc-1.0g.ai"]` |

> **Note**: The workflow supports both methods. If you set `MINER_PRIVATE_KEY` and `RPC_ENDPOINT`, all nodes will use the same credentials. If you prefer individual credentials per node, use the array format.

### Wallet Preparation

#### For Single Wallet (Option 1 - Recommended)
1. **Create one wallet** that will be used by all nodes
2. **Fund the wallet** with testnet tokens from https://faucet.0g.ai/
3. **Extract private key** (without the `0x` prefix)
4. **Add to 0G testnet** from https://docs.0g.ai/run-a-node/testnet-information

#### For Multiple Wallets (Option 2)
1. **Create multiple wallets** (one for each node you want to run)
2. **Fund each wallet** with testnet tokens from https://faucet.0g.ai/
3. **Extract private keys** (without the `0x` prefix)
4. **Add to 0G testnet** from https://docs.0g.ai/run-a-node/testnet-information

## ⚙️ Configuration

### 1. Repository Secrets Setup

Go to your repository's `Settings > Secrets and variables > Actions` and add:

#### For Single Credentials (Recommended):
```
MINER_PRIVATE_KEY: your_private_key_without_0x
RPC_ENDPOINT: https://evmrpc-testnet.0g.ai
```

#### For Individual Credentials (Advanced):
```json
MINER_PRIVATE_KEYS: ["privatekey1", "privatekey2", "privatekey3", "privatekey4", "privatekey5"]
RPC_ENDPOINTS: ["https://evmrpc-testnet.0g.ai", "https://rpc-2.0g.ai"]
```

### 2. Workflow Configuration

Edit `.github/workflows/0g-storage-nodes.yml` if needed:

```yaml
# Change default node count
node_count:
  default: '10'  # Run 10 nodes instead of 5

# Modify schedule (currently every 6 hours)
schedule:
  - cron: '0 */3 * * *'  # Every 3 hours instead
```

### 3. Node Configuration

The `config/config.template.toml` file contains the base configuration that will be customized for each node instance. Each node automatically gets:

- **Unique RPC Port**: 5679, 5680, 5681, etc. (5678 + node_id)
- **Unique Network Port**: 1235, 1236, 1237, etc. (1234 + node_id)
- **Same Wallet**: All nodes use the same private key and RPC endpoint
- **Separate Database**: Each node maintains its own sync state

## 🚀 Running the Nodes

### Method 1: Manual Trigger

1. Go to your repository's **Actions** tab
2. Select **"0G Storage Nodes - Parallel Deployment"** workflow  
3. Click **"Run workflow"**
4. Specify the number of nodes (default: 5)
5. Click **"Run workflow"** button

### Method 2: Automatic Schedule

The workflow automatically runs every 6 hours at:
- 00:00 UTC (12:00 AM)
- 06:00 UTC (6:00 AM) 
- 12:00 UTC (12:00 PM)
- 18:00 UTC (6:00 PM)

### Method 3: API Trigger

```bash
curl -X POST \
  -H "Authorization: token YOUR_GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  https://api.github.com/repos/YOUR_USERNAME/YOUR_REPO/actions/workflows/0g-storage-nodes.yml/dispatches \
  -d '{"ref":"main","inputs":{"node_count":"5"}}'
```

## 📊 Monitoring

### Real-time Monitoring

During execution, you can monitor your nodes by:

1. **GitHub Actions UI**: Go to Actions tab and click on running workflow
2. **Live logs**: Click on individual node jobs to see real-time logs
3. **Node status**: Check sync height and peer connections in logs

### Log Outputs

Each node produces detailed logs showing:

```
[2024-01-15 10:30:45] Node 1 Status - Sync Height: 1234567, Peers: 8, Runtime: 45m
[2024-01-15 10:31:15] Node 1 has been running for 45 minutes (350 max)
```

### Artifacts

After each run, the following artifacts are available:

- **Node Logs**: Individual log files for each node
- **Node Stats**: JSON files with sync status and performance metrics  
- **Summary Report**: Combined report of all nodes' performance

### Example Stats Output

```json
{
  "node_id": "1",
  "final_sync_height": "1234567", 
  "connected_peers": "8",
  "uptime_minutes": 350,
  "status": "stopped",
  "shutdown_reason": "graceful"
}
```

## 🔧 Troubleshooting

### Common Issues

#### 1. Node Failed to Start

**Symptoms**: Node process exits immediately
**Solutions**:
- Check if private key is valid (no `0x` prefix)
- Verify RPC endpoint is accessible
- Ensure wallet has sufficient testnet funds

#### 2. Low Peer Count

**Symptoms**: `connected_peers: 0` or very low number
**Solutions**:
- Check network connectivity
- Verify boot nodes are accessible
- Wait longer for peer discovery (can take 5-10 minutes)

#### 3. Sync Not Progressing

**Symptoms**: `sync_height` stays the same
**Solutions**:
- Check if RPC endpoint is synced
- Verify log contract address is correct
- Ensure system time is accurate

#### 4. Cache Issues

**Symptoms**: Node starts from scratch every time
**Solutions**:
- Check if cache is being saved correctly
- Verify artifact storage limits aren't exceeded
- Ensure cleanup script is running properly

### Debug Mode

To enable debug mode, add this to your workflow:

```yaml
env:
  DEBUG: "true"
  LOG_LEVEL: "debug"
```

### Manual Cleanup

If needed, you can manually clear the cache:

1. Go to **Actions** tab
2. Click **"Caches"** in the sidebar
3. Delete relevant cache entries

## 📁 File Structure

```
OG-labs/
├── .github/workflows/
│   └── 0g-storage-nodes.yml          # Main workflow file
├── scripts/
│   ├── setup-node.sh                 # Node setup and dependencies
│   ├── run-node.sh                   # Node execution with monitoring  
│   └── cleanup.sh                    # State cleanup and persistence
├── config/
│   └── config.template.toml           # Configuration template
└── README-github-actions.md           # This documentation
```

### Script Purposes

| Script | Purpose |
|--------|---------|
| `setup-node.sh` | Install Rust, Go, build 0G node, download snapshot |
| `run-node.sh` | Start node, monitor health, handle 6-hour runtime |
| `cleanup.sh` | Save state, compress logs, prepare for restart |

## 🎛 Advanced Configuration

### Custom Node Count

You can run different numbers of nodes by modifying the default in the workflow:

```yaml
inputs:
  node_count:
    default: '10'  # Run 10 nodes
```

### Custom Runtime

To change the 6-hour runtime, edit `run-node.sh`:

```bash
MAX_RUNTIME=14400  # 4 hours instead of ~6 hours
```

### Resource Limits

GitHub Actions provides:
- **6 hours max** per job (we use ~5h 50min)
- **2 CPU cores** per runner
- **7 GB RAM** per runner  
- **14 GB disk space** per runner

## 📈 Performance Tips

1. **Snapshot Usage**: The setup automatically downloads snapshots for faster initial sync
2. **State Persistence**: Database state is preserved between runs using GitHub cache
3. **Parallel Execution**: Multiple nodes run simultaneously for maximum efficiency
4. **Resource Optimization**: Scripts are optimized for GitHub Actions environment

## 🆘 Support

### Getting Help

1. **Check Issues**: Look at repository issues for common problems
2. **Check Logs**: Review GitHub Actions logs for error messages
3. **Community**: Join 0G Network community channels

### Useful Links

- [0G Network Docs](https://docs.0g.ai/)
- [Testnet Information](https://docs.0g.ai/run-a-node/testnet-information)
- [Faucet](https://faucet.0g.ai/)
- [Explorer](https://chainscan-galileo.0g.ai/)
- [Storage Scanner](https://storagescan-galileo.0g.ai/)

---

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

**Happy Mining! 🚀**