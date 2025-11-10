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

    struct ValidationResult {
        bool isValid;
        bytes32[] reasonCodes;
        string[] reasonMessages;
    }

    function validate(
        address trader,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        TradeContext calldata ctx
    ) external view returns (bool ok, bytes32 reasonCode);
}
