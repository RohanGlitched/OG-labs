# 🚀 Quick Setup Guide - Single Wallet for All Nodes

This is the **simplest way** to get multiple 0G Storage Nodes running on GitHub Actions using the same wallet and RPC for all nodes.

## ⚡ Super Quick Start (5 minutes)

### 1. Fork This Repository
Click the "Fork" button at the top of this repository.

### 2. Set Up Your Wallet
1. Go to https://faucet.0g.ai/ and create/fund a wallet
2. Copy your **private key** (remove the `0x` prefix if present)

### 3. Add GitHub Secrets
1. Go to your forked repository
2. Click `Settings` → `Secrets and variables` → `Actions`
3. Click `New repository secret` and add these two secrets:

```
Name: MINER_PRIVATE_KEY
Value: your_private_key_without_0x_prefix
```

```
Name: RPC_ENDPOINT  
Value: https://evmrpc-testnet.0g.ai
```

### 4. Run the Nodes
1. Go to `Actions` tab in your repository
2. Click on `0G Storage Nodes - Parallel Deployment`
3. Click `Run workflow`
4. Enter number of nodes you want (e.g., `5`)
5. Click `Run workflow` button

**That's it!** Your nodes will start running and automatically restart every 6 hours.

## 🎯 What Happens Next

### Automatic Operation
- **5 nodes** will start simultaneously (or whatever number you chose)
- Each node gets a **unique port** (5679, 5680, 5681, etc.)
- All nodes use the **same wallet** and **same RPC**
- Nodes run for **~6 hours** then gracefully restart
- **State is preserved** between restarts (no re-sync needed)
- Runs **24/7** automatically with cron schedule

### Monitoring Your Nodes
1. **Live Logs**: Click on any running job to see real-time logs
2. **Status Updates**: Look for messages like:
   ```
   Node 1 Status - Sync Height: 1234567, Peers: 8, Runtime: 45m
   ```
3. **Artifacts**: After each run, download logs and stats from the workflow page

### Check Your Mining
- **Explorer**: https://chainscan-galileo.0g.ai/ (paste your wallet address)
- **Storage Scanner**: https://storagescan-galileo.0g.ai/miner/YOUR_WALLET_ADDRESS

## 🔧 Common Questions

**Q: Can I use the same private key for all nodes?**
A: Yes! That's exactly what this setup does. All nodes will mine to the same wallet.

**Q: Will nodes conflict with each other?**
A: No, each node gets unique ports and separate database storage.

**Q: How do I change the number of nodes?**
A: Just run the workflow again with a different number.

**Q: How do I stop the nodes?**
A: Disable the workflow in the Actions tab, or delete the `.github/workflows/0g-storage-nodes.yml` file.

**Q: Do I need to do anything after 6 hours?**
A: No, nodes automatically restart and resume where they left off.

## 📊 Expected Performance

With this setup, you should see:
- **5+ connected peers** within 10 minutes
- **Sync progressing** steadily 
- **Automatic restarts** every 6 hours
- **Continuous mining** 24/7

## 🆘 Need Help?

If something isn't working:
1. Check the **Actions** tab for any failed workflows
2. Click on the failed job to see error logs
3. Verify your secrets are set correctly
4. Make sure your wallet has testnet funds

**Happy Mining! 🎉**