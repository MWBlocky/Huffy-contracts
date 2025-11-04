// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ITradeValidator {
    struct TradeContext {
        uint256 maxTradeBps;
        uint256 maxSlippageBps;
        uint256 tradeCooldownSec;
        uint256 lastTradeTimestamp;
        uint256 cooldownRemaining;
        uint256 treasuryBalance;
        uint256 maxAllowedAmount;
        uint256 impliedSlippage;
        bool pairWhitelisted;
    }

    /**
     * @dev reasonCode should map to the Relay.RejectionReason enum index
     */
    function validate(
        address trader,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        TradeContext calldata ctx
    ) external view returns (bool ok, uint8 reasonCode);
}


