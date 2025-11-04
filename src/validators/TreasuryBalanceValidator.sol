// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ITradeValidator} from "../interfaces/ITradeValidator.sol";

contract TreasuryBalanceValidator is ITradeValidator {
    function validate(
        address,
        address,
        address,
        uint256 amountIn,
        uint256,
        TradeContext calldata ctx
    ) external pure returns (bool ok, uint8 reasonCode) {
        if (ctx.treasuryBalance < amountIn) {
            return (false, uint8(4)); // INSUFFICIENT_TREASURY_BALANCE
        }
        return (true, 0);
    }
}


