// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "drosera-contracts/interfaces/ITrap.sol";

/// Minimal ERC20 interface used by collect()
interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
}

/**
 * FlashLoanSpikeTrap (production-ready)
 *
 * - Uses try/catch for ERC20.balanceOf to avoid reverts on quirky tokens / RPCs.
 * - Enforces MAX_BLOCK_WINDOW to avoid ancient peaks triggering.
 * - Implements rising-edge guard (stateless / pure) by simulating the previous window:
 *     only fires if the detection would NOT have been true in the previous sample window.
 * - Pure `shouldRespond()` (matches ITrap) and lean `collect()` (balance + block.number).
 *
 * NOTES:
 * - SPIKE_THRESHOLD is expressed in token base units (assumes 18 decimals by default).
 *   Adjust if the token uses different decimals or provide threshold in base units.
 */
contract FlashLoanSpikeTrap is ITrap {
    // -------------------------
    // User / token configuration
    // -------------------------
    address public constant TOKEN = 0x499b095Ed02f76E56444c242EC43A05F9c2A3ac8;
    address public constant MONITORED = 0x0CECAEb1b4AEb68511329BCD1844D76c66347f31;

    // Threshold (in token base units). For an 18-decimal token 0.01 = 1e16.
    uint256 public constant SPIKE_THRESHOLD = 10**16; // 0.01 tokens if decimals = 18

    // -------------------------
    // Detection tunables (compile-time constants)
    // -------------------------
    uint256 public constant WINDOW_SAMPLES = 6;          // inspect up to 6 most recent samples
    uint256 public constant MAX_BLOCK_WINDOW = 6;        // peak must be within 6 blocks of newest (0 disables)
    uint256 public constant MIN_DROP_AFTER_PEAK = SPIKE_THRESHOLD / 4; // require an immediate drop after peak

    string public constant TRAP_NAME = "FlashLoanSpikeTrap_v1";

    // -------------------------
    // collect() — lean + robust
    // -------------------------
    /// @notice returns (balance, block.number). Uses try/catch to avoid reverting on bad tokens.
    function collect() external view override returns (bytes memory) {
        uint256 bal = 0;
        // try/catch protects against non-standard ERC20s that revert on staticcall
        try IERC20(TOKEN).balanceOf(MONITORED) returns (uint256 b) {
            bal = b;
        } catch {
            // keep bal = 0 on failure (safe default for monitoring)
            bal = 0;
        }
        return abi.encode(bal, block.number);
    }

    // -------------------------
    // shouldRespond() — pure detection logic
    // -------------------------
    /**
     * Drosera ordering: data[0] = newest sample, data[1] = previous, ...
     *
     * Detection steps:
     * 1) inspect up to WINDOW_SAMPLES (or available)
     * 2) find peak (max balance) among those samples (peakIdx > 0 required)
     * 3) require peakBalance - latestBalance >= SPIKE_THRESHOLD
     * 4) require peakBlock <= latestBlock and latestBlock - peakBlock <= MAX_BLOCK_WINDOW (if enabled)
     * 5) require immediate drop after peak: peakBalance - afterPeakBalance >= MIN_DROP_AFTER_PEAK
     * 6) rising-edge guard: simulate previous-window detection (offset +1). If previous-window would also trigger,
     *    do NOT trigger now (this prevents repeated alerts for the same sustained condition).
     */
    function shouldRespond(bytes[] calldata data)
        external
        pure
        override
        returns (bool, bytes memory)
    {
        uint256 len = data.length;
        if (len < 2) return (false, bytes("")); // need at least two samples

        uint256 inspect = len;
        if (inspect > WINDOW_SAMPLES) inspect = WINDOW_SAMPLES;

        // Run detection for offset 0 (current window)
        (bool curDetect, bytes memory curPayload) = _detectAtOffset(data, 0, inspect);
        if (!curDetect) return (false, bytes(""));

        // Rising-edge guard: if previous window (offset=1) would also detect, suppress now
        if (len > 2) {
            uint256 prevInspect = (len - 1) < WINDOW_SAMPLES ? (len - 1) : WINDOW_SAMPLES;
            (bool prevDetect, ) = _detectAtOffset(data, 1, prevInspect);
            if (prevDetect) {
                // previous-window already satisfied detection => not a rising edge
                return (false, bytes(""));
            }
        }

        return (true, curPayload);
    }

    // -------------------------
    // Internal helpers
    // -------------------------
    /**
     * @dev Detect at a window starting at `offset`:
     *      treats data[offset] as "newest" for that simulated window,
     *      inspects up to `inspect` samples starting at offset..offset+inspect-1.
     *
     * Returns (true, payload) if detection criteria met.
     */
    function _detectAtOffset(
        bytes[] calldata data,
        uint256 offset,
        uint256 inspect
    ) internal pure returns (bool, bytes memory) {
        // bounds
        if (data.length <= offset + 1) return (false, bytes("")); // need at least 2 samples in this window

        // decode newest for this simulated window
        (uint256 latestBalance, uint256 latestBlock) =
            abi.decode(data[offset], (uint256, uint256));

        // Find peak among samples offset..offset+inspect-1
        uint256 peakBalance = 0;
        uint256 peakIdx = 0;
        uint256 peakBlock = 0;

        for (uint256 i = 0; i < inspect; ++i) {
            uint256 idx = offset + i;
            if (idx >= data.length) break;
            (uint256 b, uint256 blk) = abi.decode(data[idx], (uint256, uint256));
            if (b > peakBalance) {
                peakBalance = b;
                peakIdx = i; // i relative to offset (0 is newest)
                peakBlock = blk;
            }
        }

        // Peak must be older than the newest sample (peakIdx > 0)
        if (peakIdx == 0) return (false, bytes(""));

        // require a meaningful spike: peak - latest >= SPIKE_THRESHOLD
        if (peakBalance <= latestBalance) return (false, bytes(""));
        uint256 delta = peakBalance - latestBalance;
        if (delta < SPIKE_THRESHOLD) return (false, bytes(""));

        // block ordering & MAX_BLOCK_WINDOW enforcement (if enabled)
        if (latestBlock < peakBlock) return (false, bytes(""));
        if (MAX_BLOCK_WINDOW != 0) {
            uint256 diff = latestBlock - peakBlock;
            if (diff > MAX_BLOCK_WINDOW) return (false, bytes(""));
        }

        // confirm immediate drop after peak (the sample one step newer than peak)
        // peakIdx >= 1 guaranteed
        uint256 afterPeakIndex = offset + (peakIdx - 1);
        if (afterPeakIndex >= data.length) return (false, bytes(""));
        (uint256 afterPeakBalance, ) = abi.decode(data[afterPeakIndex], (uint256, uint256));
        if (peakBalance - afterPeakBalance < MIN_DROP_AFTER_PEAK) return (false, bytes(""));

        // Compose structured payload:
        // (peakBalance, latestBalance, delta, peakBlock, latestBlock, peakIdx, TOKEN, MONITORED)
        bytes memory payload = abi.encode(
            peakBalance,
            latestBalance,
            delta,
            peakBlock,
            latestBlock,
            peakIdx,
            TOKEN,
            MONITORED
        );
        return (true, payload);
    }
}
