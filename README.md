# ⚡ FlashLoanSpikeTrap

A **Drosera-compatible trap** designed to detect **suspicious flash loan activity** on-chain by monitoring rapid token balance spikes followed by immediate drops — a common pattern in flash loan-based attacks.

---

## 📖 Overview

The **FlashLoanSpikeTrap** monitors a specific address for transient balance spikes that match flash loan behavior.  
It encodes sampled balance data, detects peaks, and triggers responses when the change exceeds a defined threshold.

This trap can be used to **automate on-chain responses** or **alert systems** in the Drosera network.

---

## 🧩 Key Features

- 🪙 **ERC20 Balance Tracking:** Observes token balances for a given address.  
- ⚡ **Spike Detection:** Identifies rapid balance spikes and immediate drops.  
- 🧠 **Threshold Logic:** Configurable spike detection threshold (e.g., `0.01 tokens`).  
- 🧍 **Pure Analysis Mode:** Safe to run during dry runs or simulation (no on-chain calls).  
- 🔒 **Drosera-Compatible:** Implements `ITrap` interface for Drosera’s security network.

---

## ⚙️ Trap Logic Summary

| Parameter | Description | Example |
|------------|--------------|----------|
| **TOKEN** | Address of token being monitored | `0x499b095Ed02f76E56444c242EC43A05F9c2A3ac8` |
| **MONITORED** | Wallet or contract address under watch | `0x0CECAEb1b4AEb68511329BCD1844D76c66347f31` |
| **SPIKE_THRESHOLD** | Minimum balance change considered a flash loan spike | `10**16` (0.01 tokens) |
| **WINDOW_SAMPLES** | Number of samples Drosera gathers for analysis | Set in constructor |
| **MAX_BLOCK_WINDOW** | Max block distance between samples (optional) | Configurable |
| **MIN_DROP_AFTER_PEAK** | Required drop percentage to confirm spike | Configurable |

---

## 📜 Example Code Snippet

```solidity
function collect() external view override returns (bytes memory) {
    // Mock response for dryrun testing (no external calls)
    return abi.encode(uint256(1e18), block.number);
}```

This function collects a snapshot of the token balance and block number, used in comparisons by `shouldRespond()`.


---

##🧮 Trap Behavior (Simplified)

1. Collect balance samples from monitored address.


2. Find peak balance value among recent samples.


3. Detect if a sharp drop follows immediately.


4. Trigger response if:

Spike magnitude > `SPIKE_THRESHOLD`

Newest sample < peak sample

Time window fits constraints





---

##🧰 drosera.toml Example

```name = "flash_loan_spike_trap"
description = "Detects transient flash loan spikes in monitored balances"
contract = "src/FlashLoanSpikeTrap.sol:FlashLoanSpikeTrap"

[cooldown]
blocks = 10```


---

##🪄 Setup Instructions

1. Clone this repo

```git clone https://github.com/<your-username>/FlashLoanSpikeTrap.git
cd FlashLoanSpikeTrap```


2. Build with Foundry

```forge build```


3. Dry run with Drosera

```drosera dryrun```




---

##🧠 Author


💬 Twitter: [Samadfrmdtrench](https://x.com/Biggdawgg06)

🌐 Project: [Drosera Network](https://drosera.io)


---
