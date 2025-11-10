// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ITradeValidator} from "../interfaces/ITradeValidator.sol";

contract MaxTradeSizeValidator is ITradeValidator {
    function validate(
        address,
        address,
        address,
        uint256 amountIn,
        uint256,
        TradeContext calldata ctx
    ) external pure returns (bool ok, bytes32 reasonCode) {
        if (amountIn > ctx.maxAllowedAmount) {
            return (false, keccak256("EXCEEDS_MAX_TRADE_SIZE"));
        }
        return (true, bytes32(0));
    }
}


