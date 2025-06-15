// SPDX-License-Identifier: Apache 2.0
pragma solidity 0.8.19;

import "./RootERC20BridgeFlowRate.sol";

/**
 * @title  Root ERC20 Bridge Flow Rate – Patched Version
 * @notice Introduces gas-aware guards that bound the work each call can perform.
 *         This mitigates DoS risk from un-bounded loops in
 *         `finaliseQueuedWithdrawalsAggregated` and `findPendingWithdrawals`.
 */
contract RootERC20BridgeFlowRatePatched is RootERC20BridgeFlowRate {
    // ---------------------------------------------------------------------
    // Constants
    // ---------------------------------------------------------------------

    /// @dev Maximum number of queue indices that can be processed in a single
    ///      `finaliseQueuedWithdrawalsAggregated` call.
    uint256 public constant MAX_AGGREGATED_WITHDRAWALS = 1000;

    /// @dev Maximum scan window `(stopIndex - startIndex)` that can be examined
    ///      by `findPendingWithdrawals`.
    uint256 public constant MAX_SCAN_RANGE = 4096;

    // ---------------------------------------------------------------------
    // Custom errors
    // ---------------------------------------------------------------------

    /// @dev Thrown when `indices.length` exceeds `MAX_AGGREGATED_WITHDRAWALS`.
    error TooManyIndices(uint256 provided, uint256 maxAllowed);

    /// @dev Thrown when `(stopIndex - startIndex)` exceeds `MAX_SCAN_RANGE`.
    error ScanRangeTooLarge(uint256 provided, uint256 maxAllowed);

    // ---------------------------------------------------------------------
    // Constructor
    // ---------------------------------------------------------------------

    constructor(address initializerAddress) RootERC20BridgeFlowRate(initializerAddress) {}

    // ---------------------------------------------------------------------
    // Overridden functions with guards
    // ---------------------------------------------------------------------

    /// @notice Gas-bounded variant of `finaliseQueuedWithdrawalsAggregated` that
    ///         enforces `MAX_AGGREGATED_WITHDRAWALS` and prevents block gas DoS.
    /// @param receiver The user receiving funds.
    /// @param token    The token to withdraw.
    /// @param indices  Indices into the caller's withdrawal queue to aggregate.
    function finaliseQueuedWithdrawalsAggregatedLimited(address receiver, address token, uint256[] calldata indices)
        public
        nonReentrant
    {
        if (indices.length == 0) {
            revert ProvideAtLeastOneIndex();
        }
        if (indices.length > MAX_AGGREGATED_WITHDRAWALS) {
            revert TooManyIndices(indices.length, MAX_AGGREGATED_WITHDRAWALS);
        }

        uint256 total = 0;
        address withdrawer = address(0);

        for (uint256 i = 0; i < indices.length; i++) {
            address actualToken;
            uint256 amount;
            (withdrawer, actualToken, amount) = _processWithdrawal(receiver, indices[i]);

            if (actualToken != token) {
                revert MixedTokens(token, actualToken);
            }

            total += amount;
        }

        address childToken = rootTokenToChildToken[token];
        _executeTransfer(token, childToken, withdrawer, receiver, total);
    }

    /// @notice Gas-bounded wrapper around `findPendingWithdrawals` that enforces `MAX_SCAN_RANGE`.
    function findPendingWithdrawalsLimited(
        address receiver,
        address token,
        uint256 startIndex,
        uint256 stopIndex,
        uint256 maxFind
    ) public view returns (FindPendingWithdrawal[] memory found) {
        if (stopIndex < startIndex) {
            return new FindPendingWithdrawal[](0);
        }
        uint256 scanLen = stopIndex - startIndex;
        if (scanLen > MAX_SCAN_RANGE) {
            revert ScanRangeTooLarge(scanLen, MAX_SCAN_RANGE);
        }

        // Call the original unbounded implementation once bounds are satisfied.
        found = this.findPendingWithdrawals(receiver, token, startIndex, stopIndex, maxFind);
    }
}
