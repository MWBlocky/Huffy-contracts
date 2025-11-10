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
    ) external pure returns (bool ok, bytes32 reasonCode) {
        if (ctx.treasuryBalance < amountIn) {
            return (false, keccak256("INSUFFICIENT_TREASURY_BALANCE"));
        }
        return (true, bytes32(0));
    }
}


