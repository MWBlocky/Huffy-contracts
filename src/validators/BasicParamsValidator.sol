// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ITradeValidator} from "../interfaces/ITradeValidator.sol";

contract BasicParamsValidator is ITradeValidator {
    function validate(
        address,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        TradeContext calldata
    ) external pure returns (bool ok, uint8 reasonCode) {
        if (tokenIn == address(0) || tokenOut == address(0) || amountIn == 0 || minAmountOut == 0) {
            return (false, uint8(5)); // INVALID_PARAMETERS (must match Relay enum index)
        }
        return (true, 0);
    }
}


