// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "drosera-contracts/interfaces/ITrap.sol";

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
}

/**
 * FlashLoanSpikeTrap (no-arg constructor version)
 *
 * This variant uses sensible DEFAULT constants so Drosera can deploy it in dryrun
 * without needing constructor parameters.
 */
contract FlashLoanSpikeTrap is ITrap {
    // User constants
    address public constant TOKEN = 0x499b095Ed02f76E56444c242EC43A05F9c2A3ac8;
    address public constant MONITORED = 0x0CECAEb1b4AEb68511329BCD1844D76c66347f31;

    // 0.01 tokens with 18 decimals
    uint256 public constant SPIKE_THRESHOLD = 10**16;

    // DEFAULT Tunables (no constructor required)
    uint256 public constant WINDOW_SAMPLES = 6;       // inspect up to 6 most recent samples
    uint256 public constant MAX_BLOCK_WINDOW = 6;     // peak must be within 6 blocks of newest (0 disables)
    uint256 public constant MIN_DROP_AFTER_PEAK = SPIKE_THRESHOLD / 4; // immediate drop requirement

    string public constant trapName = "FlashLoanSpikeTrap_v1";

    /// @notice Returns the current token balance and block number.
    /// For dryrun safety we return a mock balance (so collect() never reverts).
    function collect() external view override returns (bytes memory) {
        // NOTE: replace the mock below with the real call if you want live data:
        // uint256 bal = IERC20(TOKEN).balanceOf(MONITORED);
        // return abi.encode(bal, block.number);

        // Mock response for dryrun testing (no external calls)
        return abi.encode(uint256(1e18), block.number);
    }

    /**
     * @notice Analyzes samples to detect a flash-loan-like spike.
     * @dev data[0] is newest; data[1] is previous; etc.
     */
    function shouldRespond(bytes[] calldata data)
        external
        pure
        override
        returns (bool, bytes memory)
    {
        uint256 len = data.length;
        if (len < 2) return (false, bytes(""));

        // Limit scan window to the smaller of len and WINDOW_SAMPLES (but WINDOW_SAMPLES is constant)
        uint256 inspect = len;
        if (inspect > WINDOW_SAMPLES) inspect = WINDOW_SAMPLES;

        // Decode newest
        (uint256 latestBalance, uint256 latestBlock) =
            abi.decode(data[0], (uint256, uint256));

        uint256 peakBalance;
        uint256 peakIdx;
        uint256 peakBlock;

        // Find the max balance among samples
        for (uint256 i = 0; i < inspect; ++i) {
            (uint256 b, uint256 blk) = abi.decode(data[i], (uint256, uint256));
            if (b > peakBalance) {
                peakBalance = b;
                peakIdx = i;
                peakBlock = blk;
            }
        }

        // Require the peak not be the newest sample
        if (peakIdx == 0) return (false, bytes(""));

        // Check for a meaningful drop
        if (peakBalance <= latestBalance) return (false, bytes(""));
        uint256 delta = peakBalance - latestBalance;
        if (delta < SPIKE_THRESHOLD) return (false, bytes(""));

        // Basic sanity on block ordering
        if (latestBlock < peakBlock) return (false, bytes(""));

        // confirm after-peak immediate drop
        (uint256 afterPeakBalance, ) = abi.decode(data[peakIdx - 1], (uint256, uint256));
        if (peakBalance - afterPeakBalance < MIN_DROP_AFTER_PEAK) return (false, bytes(""));

        // All checks passed — structured payload:
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
